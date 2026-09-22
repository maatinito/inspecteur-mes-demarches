# frozen_string_literal: true

module Dbs
  # Au dépôt d'un engagement d'éleveur (démarche 4038), inscrit cet engagement
  # dans le laissez-passer qu'il désigne (démarche 3899) : la zone
  # « Engagements reçus » est réécrite en entier avec l'engagement ajouté, la
  # zone « Engagements manquants » avec les éleveurs du bloc qui n'ont pas
  # encore signé (rapprochement par courriel du compte, en minuscules).
  #
  # C'est ainsi que le laissez-passer connaît ses engagements : l'API GraphQL
  # ne filtre pas les dossiers par valeur de champ, le lien inverse se construit
  # à l'écriture (spec §3.2, décision 17). Écrire dans le laissez-passer le fait
  # repasser en inspection, ce qui servira au visa (tranche suivante).
  class EngagementRecu < FieldChecker
    ETATS_PAR_DEFAUT = %w[en_construction en_instruction accepte].freeze

    def version
      super + 1
    end

    def required_fields
      super + %i[champ_laissez_passer champ_eleveurs annotation_recus annotation_manquants]
    end

    def authorized_fields
      super + %i[champ_nom champ_nom_eleveur champ_email_eleveur champ_tel_eleveur]
    end

    def initialize(params)
      super
      @states = Set.new(ETATS_PAR_DEFAUT) if @params[:etat_du_dossier].blank?
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      numero = field(@params[:champ_laissez_passer])&.string_value.to_s[/\d+/]
      if numero.blank?
        Rails.logger.warn("Engagement #{dossier.number} : aucun laissez-passer lié, rien à faire")
        return
      end

      laissez_passer = DossierActions.on_dossier(numero.to_i)
      raise "Laissez-passer #{numero} introuvable depuis l'engagement #{dossier.number}" if laissez_passer.nil?

      eleveurs = eleveurs_du_lot(laissez_passer)
      engagements = ListeEngagements.upsert(ListeEngagements.parse_recus(texte_annotation(laissez_passer, :annotation_recus)),
                                            engagement_courant(eleveurs))
      ecrire(laissez_passer, :annotation_recus, ListeEngagements.format_recus(engagements))
      ecrire(laissez_passer, :annotation_manquants, ListeEngagements.format_manquants(eleveurs, engagements))
    end

    private

    def engagement_courant(eleveurs)
      email = @dossier.usager&.email.to_s.strip.downcase
      ListeEngagements::Engagement.new(nom: nom_eleveur, email:, numero: @dossier.number,
                                       date: Date.parse(@dossier.date_depot),
                                       attendu: eleveurs.any? { |e| e[:email] == email })
    end

    def nom_eleveur
      nom = champ_value(field(@params[:champ_nom] || "Nom et prénom de l'éleveur", warn_if_empty: false)).to_s.strip
      return nom if nom.present?

      demandeur = @dossier.demandeur
      demandeur.respond_to?(:entreprise) ? demandeur.entreprise&.raison_sociale.to_s : ''
    end

    def eleveurs_du_lot(laissez_passer)
      rows = dossier_field(laissez_passer, @params[:champ_eleveurs], warn_if_empty: false)&.rows || []
      rows.map do |row|
        { nom: valeur(row, @params[:champ_nom_eleveur] || "Nom et Prénom de l'éleveur"),
          email: valeur(row, @params[:champ_email_eleveur] || "Email de l'éleveur").downcase,
          telephone: valeur(row, @params[:champ_tel_eleveur] || "Téléphone de l'éleveur") }
      end
    end

    def valeur(row, label)
      champs_to_values(select_champ(row.champs, label)).first.to_s.strip
    end

    def texte_annotation(laissez_passer, cle)
      SetAnnotationValue.get_annotation(laissez_passer, @params[cle])&.value.to_s
    end

    def ecrire(laissez_passer, cle, texte)
      SetAnnotationValue.set_value(laissez_passer, instructeur_id, @params[cle], texte)
    end
  end
end
