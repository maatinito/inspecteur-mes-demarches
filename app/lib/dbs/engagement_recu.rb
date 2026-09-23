# frozen_string_literal: true

module Dbs
  # Au dépôt d'un engagement d'éleveur (démarche 4038), inscrit cet engagement
  # dans le laissez-passer qu'il désigne (démarche 3899) : la zone
  # « Engagements reçus » est réécrite en entier avec l'engagement ajouté, la
  # zone « Engagements manquants » avec les éleveurs du bloc qui n'ont pas
  # encore signé. Le rapprochement se fait sur l'annotation privée « Courriel
  # d'attribution » : préremplie par le lien d'invitation (une annotation
  # privée se préremplit par l'URL comme un champ public, sans être visible de
  # l'usager), ou corrigée par l'agent ; à défaut, le robot la déduit du
  # téléphone concordant, sinon du courriel du compte, et n'écrit l'annotation
  # que lorsqu'il l'a déduite.
  #
  # C'est ainsi que le laissez-passer connaît ses engagements : l'API GraphQL
  # ne filtre pas les dossiers par valeur de champ, le lien inverse se construit
  # à l'écriture (spec §3.2, décision 17). Écrire dans le laissez-passer le fait
  # repasser en inspection, ce qui servira au visa (tranche suivante).
  #
  # Les paramètres sont regroupés par dossier, dans deux sous-blocs :
  #   engagement:      le dossier courant (démarche 4038)
  #   laissez_passer:  le dossier lié (démarche 3899)
  class EngagementRecu < FieldChecker
    ETATS_PAR_DEFAUT = %w[en_construction en_instruction accepte].freeze
    ENGAGEMENT_REQUIS = %i[lien_laissez_passer].freeze
    ENGAGEMENT_DEFAUTS = { nom: "Nom et prénom de l'éleveur", telephone: 'Téléphone',
                           courriel_attribution: nil }.freeze
    LAISSEZ_PASSER_REQUIS = %i[eleveurs engagements_recus engagements_manquants].freeze
    LAISSEZ_PASSER_DEFAUTS = { demarche: nil, nom_eleveur: "Nom et Prénom de l'éleveur",
                               email_eleveur: "Email de l'éleveur", telephone_eleveur: "Téléphone de l'éleveur" }.freeze

    def version
      super + 3
    end

    def required_fields
      super + %i[engagement laissez_passer]
    end

    def initialize(params)
      super
      @states = Set.new(ETATS_PAR_DEFAUT) if @params[:etat_du_dossier].blank?
      return unless valid?

      @engagement = sous_bloc(:engagement, ENGAGEMENT_REQUIS, ENGAGEMENT_DEFAUTS)
      @laissez_passer = sous_bloc(:laissez_passer, LAISSEZ_PASSER_REQUIS, LAISSEZ_PASSER_DEFAUTS)
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      numero = field(@engagement[:lien_laissez_passer])&.string_value.to_s[/\d+/]
      if numero.blank?
        Rails.logger.warn("Engagement #{dossier.number} : aucun laissez-passer lié, rien à faire")
        return
      end

      laissez_passer = DossierActions.on_dossier(numero.to_i)
      raise "Laissez-passer #{numero} introuvable depuis l'engagement #{dossier.number}" if laissez_passer.nil?

      if @laissez_passer[:demarche].present? && laissez_passer.demarche.number.to_i != @laissez_passer[:demarche].to_i
        raise "Le dossier #{numero} n'est pas un laissez-passer de la démarche #{@laissez_passer[:demarche]} " \
              "(démarche #{laissez_passer.demarche.number})"
      end

      eleveurs = eleveurs_du_lot(laissez_passer)
      email = courriel_attribution(eleveurs)
      engagements = ListeEngagements.upsert(ListeEngagements.parse_recus(texte_annotation(laissez_passer, @laissez_passer[:engagements_recus])),
                                            engagement_courant(eleveurs, email))
      ecrire(laissez_passer, @laissez_passer[:engagements_recus], ListeEngagements.format_recus(engagements))
      ecrire(laissez_passer, @laissez_passer[:engagements_manquants], ListeEngagements.format_manquants(eleveurs, engagements))
    end

    private

    # Un sous-bloc YAML (engagement: / laissez_passer:) : clés requises, clés connues avec défaut,
    # tout le reste est une erreur de paramétrage signalée comme les clés de premier niveau.
    def sous_bloc(nom, requis, defauts)
      bloc = @params[nom]
      unless bloc.is_a?(Hash)
        @errors << "#{nom} doit être un bloc de clés sur dbs/engagement_recu"
        return defauts
      end

      bloc = bloc.symbolize_keys
      manquants = requis - bloc.keys
      @errors << "Clé(s) manquante(s) '#{manquants.join(', ')}' dans #{nom} sur dbs/engagement_recu" if manquants.present?
      inconnues = bloc.keys - requis - defauts.keys
      @errors << "#{inconnues.join(', ')} n'existe(nt) pas dans #{nom} sur dbs/engagement_recu" if inconnues.present?
      defauts.merge(bloc)
    end

    def engagement_courant(eleveurs, email)
      ListeEngagements::Engagement.new(nom: nom_eleveur, email:, numero: @dossier.number,
                                       date: date_depot,
                                       attendu: eleveurs.any? { |e| e[:email] == email })
    end

    # Courriel qui rattache l'engagement à une ligne du laissez-passer.
    # Priorité : annotation présente (préremplie par le lien d'invitation, ou
    # corrigée par l'agent) > téléphone concordant > courriel du compte ; le
    # robot n'écrit l'annotation que lorsqu'il l'a déduite.
    def courriel_attribution(eleveurs)
      nom_annotation = @engagement[:courriel_attribution]
      deja = nom_annotation.present? ? champ_value(annotation(nom_annotation, warn_if_empty: false)).to_s.strip.downcase : ''
      return deja if deja.present?

      email = courriel_par_telephone(eleveurs) || @dossier.usager&.email.to_s.strip.downcase
      dossier_updated(@dossier) if nom_annotation.present? && email.present? && SetAnnotationValue.set_value(@dossier, instructeur_id, nom_annotation, email)
      email
    end

    def courriel_par_telephone(eleveurs)
      tel = chiffres(champ_value(field(@engagement[:telephone], warn_if_empty: false)))
      return nil if tel.length < 6

      eleveurs.find { |e| chiffres(e[:telephone]) == tel }&.dig(:email).presence
    end

    # Comparaison de téléphones : chiffres seuls, indicatif polynésien (+689 / 00689) retiré.
    def chiffres(valeur)
      valeur.to_s.gsub(/\D/, '').sub(/\A(00)?689/, '')
    end

    def date_depot
      Time.zone.parse(@dossier.date_depot.to_s)&.to_date || Time.zone.today
    end

    def nom_eleveur
      nom = champ_value(field(@engagement[:nom], warn_if_empty: false)).to_s.strip
      return nom if nom.present?

      demandeur = @dossier.demandeur
      demandeur.respond_to?(:entreprise) ? demandeur.entreprise&.raison_sociale.to_s : ''
    end

    def eleveurs_du_lot(laissez_passer)
      rows = dossier_field(laissez_passer, @laissez_passer[:eleveurs], warn_if_empty: false)&.rows || []
      rows.map do |row|
        { nom: valeur(row, @laissez_passer[:nom_eleveur]),
          email: valeur(row, @laissez_passer[:email_eleveur]).downcase,
          telephone: valeur(row, @laissez_passer[:telephone_eleveur]) }
      end
    end

    def valeur(row, label)
      champs_to_values(select_champ(row.champs, label)).first.to_s.strip
    end

    def texte_annotation(laissez_passer, libelle)
      SetAnnotationValue.get_annotation(laissez_passer, libelle)&.value.to_s
    end

    def ecrire(laissez_passer, libelle, texte)
      SetAnnotationValue.set_value(laissez_passer, instructeur_id, libelle, texte)
    end
  end
end
