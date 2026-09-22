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
    LIGNE_ENVOI = /\A(?<email>\S+) — envoyé le (?<date>.+)\z/
    ETATS_PAR_DEFAUT = %w[en_instruction].freeze

    def version
      super + 1
    end

    def required_fields
      super + %i[demarche_engagement champ_eleveurs annotation_envois objet message prerempli]
    end

    def authorized_fields
      super + %i[champ_email champ_nom]
    end

    def initialize(params)
      super
      @states = Set.new(ETATS_PAR_DEFAUT) if @params[:etat_du_dossier].blank?
      @champ_email = @params[:champ_email] || "Email de l'éleveur"
      @champ_nom = @params[:champ_nom] || "Nom et Prénom de l'éleveur"
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      rows = param_field(:champ_eleveurs)&.rows || []
      lignes = lignes_envois
      deja = lignes.filter_map { |l| LIGNE_ENVOI.match(l)&.[](:email)&.downcase }.to_set

      rows.each do |row|
        ligne = inviter(row, deja)
        next unless ligne

        lignes << ligne
        SetAnnotationValue.set_value(dossier, instructeur_id, @params[:annotation_envois], lignes.join("\n"))
        dossier_updated(dossier)
      end
    end

    private

    def lignes_envois
      annotation(@params[:annotation_envois], warn_if_empty: false)&.value.to_s.lines.map(&:strip).reject(&:blank?)
    end

    def inviter(row, deja)
      email = valeur(row, @champ_email).downcase
      return nil if email.blank? || deja.include?(email)

      variables = { lien: PrefillURL.build(@params[:demarche_engagement], valeurs_prerempli(row)), nom_eleveur: valeur(row, @champ_nom) }
      NotificationMailer.with(subject: instanciate(@params[:objet], variables),
                              message: instanciate(@params[:message], variables),
                              recipients: email).user_mail.deliver_later
      deja << email
      Rails.logger.info("Invitation à signer l'engagement envoyée à #{email}")
      "#{email} — envoyé le #{Time.zone.now.strftime('%d/%m/%Y %H:%M')}"
    end

    def valeur(row, label)
      champs_to_values(select_champ(row.champs, label)).first.to_s.strip
    end

    def valeurs_prerempli(row)
      @params[:prerempli].to_h do |stable_id, chemin|
        champs = object_field_values(row, chemin.to_s, log_empty: false)
        champs = object_field_values(@dossier, chemin.to_s, log_empty: false) if champs.blank?
        [stable_id, champs_to_values(champs).first]
      end
    end
  end
end
