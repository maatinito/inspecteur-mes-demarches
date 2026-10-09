# frozen_string_literal: true

module Dbs
  # Surveillance quotidienne d'un carnet de suivi de poussins (spec carnet §5.2) : alerte de mortalité à la cellule
  # (une par jour signalé, trace « Alertes mortalité »), relance de l'éleveur après un silence (une par silence,
  # trace = dernier jour saisi au moment de la relance), tableau de bord de la vétérinaire (dernier jour saisi,
  # mortalité sur la fenêtre), garde-fou de prolongation (une fois par écart saisi/accordé), et rejeu planifié le
  # lendemain : un carnet silencieux n'est jamais modifié, donc jamais réinspecté sans ce rejeu.
  class SuiviCarnet < FieldChecker
    ETATS_PAR_DEFAUT = %w[en_construction en_instruction].freeze
    DEFAUTS = { seuil: 0.03, fenetre: 3, silence: 4, nb_jours: 42, heure_rejeu: 7, duree: 21 }.freeze

    def version
      super + 2
    end

    def required_fields
      super + %i[j0 recu prefixe_jour alertes relance dernier_jour mortalite destinataires_alerte objet_alerte
                 message_alerte message_relance]
    end

    def authorized_fields
      super + DEFAUTS.keys + %i[prolongation_usager prolongation_accordee ecart_signale destinataires_veterinaire
                                message_ecart]
    end

    def initialize(params)
      super
      @states = Set.new(ETATS_PAR_DEFAUT) if @params[:etat_du_dossier].blank?
      @cfg = DEFAUTS.merge(@params.to_h.symbolize_keys.slice(*DEFAUTS.keys))
    end

    def process(demarche, dossier)
      super
      unless must_check?(dossier)
        ScheduledTask.clear(task: identifiant, dossier: dossier.number)
        return
      end

      # Replanifié d'abord : une erreur plus loin (après un envoi) ne laisse pas la ligne planifiée en place,
      # que ScheduledTaskJob rejouerait chaque minute en renvoyant le même message.
      replanifier
      j0 = date_champ(@params[:j0])
      recu = entier(@params[:recu])
      if j0.nil? || recu.nil?
        Rails.logger.warn("Carnet #{dossier.number} : J0 ou effectif reçu absent, suivi impossible")
        return
      end

      morts = (1..@cfg[:nb_jours].to_i).map { |n| entier("#{@params[:prefixe_jour]} #{n}") }
      alerter(recu, morts)
      relancer((Time.zone.today - j0).to_i, morts)
      tableau_de_bord(recu, morts)
      garde_fou_prolongation
    end

    private

    def identifiant = "dbs/suivi_carnet/#{@dossier.number}"

    def alerter(recu, morts)
      deja = texte(@params[:alertes]).scan(/J(\d+)/).flatten.map(&:to_i)
      nouveaux = CarnetMortalite.jours_en_alerte(recu, morts, @cfg[:seuil].to_f) - deja
      return if nouveaux.empty?

      nouveaux.each do |n|
        variables = { jour: n, morts: morts[n - 1], restant: CarnetMortalite.restant_veille(recu, morts, n) }
        courriel(@params[:destinataires_alerte], @params[:objet_alerte], @params[:message_alerte], variables)
      end
      ecrire(@params[:alertes], (deja + nouveaux).sort.map { |n| "J#{n}" }.join(', '))
    end

    def relancer(jour, morts)
      dernier = CarnetMortalite.dernier_jour_saisi(morts)
      return if jour - dernier < @cfg[:silence].to_i || texte(@params[:relance]) == dernier.to_s

      # Jours prévus : 21 + la prolongation la plus longue (saisie par l'éleveur ou accordée) ; au-delà, les
      # champs sont masqués ou la période est finie (pas de relance après la période, spec K8).
      limite = [jour, fin_de_periode, morts.size].min
      return if dernier >= limite

      a_saisir = ((dernier + 1)..limite).to_a.join(', ')
      SendMessage.deliver_message(@dossier, instructeur_id, instanciate(@params[:message_relance], { jours_a_saisir: a_saisir }))
      ecrire(@params[:relance], dernier.to_s)
    end

    def fin_de_periode
      prolongations = [@params[:prolongation_usager], @params[:prolongation_accordee]].compact_blank.map { |l| entier(l).to_i }
      @cfg[:duree].to_i + (prolongations.max || 0)
    end

    def tableau_de_bord(recu, morts)
      ecrire(@params[:dernier_jour], CarnetMortalite.dernier_jour_saisi(morts).to_s)
      ecrire(@params[:mortalite], CarnetMortalite.mortalite_fenetre(recu, morts, @cfg[:fenetre].to_i).to_s)
    end

    def garde_fou_prolongation
      return if @params[:prolongation_accordee].blank?

      saisi = entier(@params[:prolongation_usager]).to_i
      accorde = entier(@params[:prolongation_accordee]).to_i
      paire = "#{saisi}/#{accorde}"
      return if saisi == accorde || texte(@params[:ecart_signale]) == paire

      courriel(@params[:destinataires_veterinaire], "Carnet #{@dossier.number} : prolongation à vérifier",
               @params[:message_ecart], { saisi:, accorde: })
      ecrire(@params[:ecart_signale], paire)
    end

    def replanifier
      demain = Time.zone.tomorrow.in_time_zone.change(hour: @cfg[:heure_rejeu].to_i)
      ScheduledTask.clear(task: identifiant, dossier: @dossier.number)
      ScheduledTask.enqueue(@dossier.number, identifiant, @params.except(:scheduled), demain)
    end

    def courriel(destinataires, objet, message, variables)
      NotificationMailer.with(subject: instanciate(objet, variables), message: instanciate(message.to_s, variables),
                              recipients: destinataires).user_mail.deliver_later
    end

    def ecrire(libelle, valeur)
      return if libelle.blank?

      dossier_updated(@dossier) if SetAnnotationValue.set_value(@dossier, instructeur_id, libelle, valeur)
    end

    def champ(libelle) = object_field_values(@dossier, libelle, log_empty: false).first

    def entier(libelle)
      c = champ(libelle)
      c.respond_to?(:int_value) ? c.int_value : nil
    end

    def texte(libelle) = champ(libelle)&.string_value.to_s

    def date_champ(libelle)
      valeur = champ_value(champ(libelle))
      valeur.is_a?(Date) ? valeur : nil
    end
  end
end
