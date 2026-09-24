# frozen_string_literal: true

module Dbs
  # Déclencheur n° 1 de la cascade poussins (spec §5) : pour chaque ligne du bloc
  # « Liste des éleveurs » du laissez-passer, envoie à l'éleveur un courriel
  # avec un lien prérempli vers la démarche engagement. La trace des envois est
  # l'annotation texte « Invitations envoyées » du laissez-passer, une ligne
  # « courriel — envoyé le JJ/MM/AAAA HH:MM » par éleveur : un éleveur déjà
  # présent n'est pas réinvité, un éleveur ajouté après coup l'est au passage
  # suivant. À brancher sous un conditional_field sur la case
  # « Envoyer les engagements ».
  #
  # prerempli : { stable_id (démarche engagement) => chemin de champ }, le chemin
  # est cherché d'abord dans la ligne du bloc (champs de l'éleveur), puis dans le
  # dossier (« number », « demandeur.entreprise.raison_sociale », libellé d'un champ).
  #
  # La trace est réécrite après CHAQUE envoi (pas une seule fois à la fin) : si une
  # ligne suivante fait échouer l'envoi ou l'écriture, les invitations déjà parties
  # sont déjà tracées. Risque résiduel assumé : un échec en cours de passage laisse
  # au plus UN courriel dupliqué au passage suivant (celui en cours d'écriture),
  # jamais la liste entière — l'ordre inverse (tracer puis envoyer) risquerait de
  # marquer un éleveur invité sans qu'aucun courriel ne soit parti, en silence.
  class InviterEleveurs < FieldChecker
    include Dbs::EleveursDuLot

    LIGNE_ENVOI = /\A(?<email>\S+) — envoyé le (?<date>.+)\z/
    ETATS_PAR_DEFAUT = %w[en_instruction].freeze

    def version
      super + 3
    end

    def required_fields
      super + %i[demarche_engagement eleveurs invitations_envoyees objet message prerempli]
    end

    def authorized_fields
      super + %i[email_eleveur nom_eleveur telephone_eleveur quantite_eleveur importateur_eleveur]
    end

    def initialize(params)
      super
      @states = Set.new(ETATS_PAR_DEFAUT) if @params[:etat_du_dossier].blank?
      @champ_email = @params[:email_eleveur] || "Email de l'éleveur"
      @champ_nom = @params[:nom_eleveur] || "Nom et Prénom de l'éleveur"
      @cfg = { eleveurs: @params[:eleveurs], nom_eleveur: @champ_nom, email_eleveur: @champ_email,
               telephone_eleveur: @params[:telephone_eleveur] || "Téléphone de l'éleveur",
               quantite_eleveur: @params[:quantite_eleveur] || 'Quantité de poussins',
               importateur_eleveur: @params[:importateur_eleveur]&.deep_symbolize_keys }
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      raise "Annotation '#{@params[:invitations_envoyees]}' introuvable sur le dossier #{dossier.number} : aucune invitation envoyée" unless annotation(@params[:invitations_envoyees],
                                                                                                                                                        warn_if_empty: false)

      lignes = lignes_envois
      deja = lignes.filter_map { |l| LIGNE_ENVOI.match(l)&.[](:email)&.downcase }.to_set

      eleveurs_du_lot(dossier, @cfg).each do |eleveur|
        ligne = inviter(eleveur, deja)
        next unless ligne

        lignes << ligne
        SetAnnotationValue.set_value(dossier, instructeur_id, @params[:invitations_envoyees], lignes.join("\n"))
        dossier_updated(dossier)
      end
    end

    private

    def lignes_envois
      annotation(@params[:invitations_envoyees], warn_if_empty: false)&.value.to_s.lines.map(&:strip).reject(&:blank?)
    end

    def inviter(eleveur, deja)
      email = eleveur[:email]
      return nil if email.blank? || deja.include?(email)

      variables = { lien: PrefillURL.build(@params[:demarche_engagement], valeurs_prerempli(eleveur)), nom_eleveur: eleveur[:nom] }
      NotificationMailer.with(subject: instanciate(@params[:objet], variables),
                              message: instanciate(@params[:message], variables),
                              recipients: email).user_mail.deliver_later
      deja << email
      Rails.logger.info("Invitation à signer l'engagement envoyée à #{email}")
      "#{email} — envoyé le #{Time.zone.now.strftime('%d/%m/%Y %H:%M')}"
    end

    def valeurs_prerempli(eleveur)
      @params[:prerempli].to_h do |stable_id, chemin|
        valeur = eleveur[:valeurs][chemin.to_s]
        valeur = champs_to_values(object_field_values(@dossier, chemin.to_s, log_empty: false)).first if valeur.nil?
        [stable_id, valeur]
      end
    end
  end
end
