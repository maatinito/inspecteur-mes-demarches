# frozen_string_literal: true

class AvisToBlocRepetable < FieldChecker
  def version
    super + 1
  end

  def required_fields
    super + %i[bloc_destination attributs]
  end

  def authorized_fields
    super + %i[baserow filtres]
  end

  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    # 1. Récupérer les avis du dossier
    avis_list = fetch_avis(dossier)
    return if avis_list.blank?

    # 2. Table Baserow si configurée
    table = baserow_table if @params[:baserow]

    # 3. Transformer chaque avis en ligne du bloc
    rows_data = avis_list.filter_map do |avis|
      next unless should_include_avis?(avis)

      # Créer le hash aplati avec toutes les données
      avis_hash = flatten_avis(avis, table)

      # Construire la ligne avec instanciate et les expressions ternaires
      row = {}
      @params[:attributs].each do |col_name, template|
        row[col_name] = instanciate(template.to_s, avis_hash)
      end
      row
    end

    return if rows_data.blank?

    # 4. Créer/mettre à jour le bloc répétable
    update_repetition_block(rows_data)
  end

  private

  def fetch_avis(dossier)
    # Requête GraphQL dédiée pour récupérer les avis (lazy loading)
    result = MesDemarches.query(Query::DossierAvis, variables: { dossier: dossier.number })

    if result.errors.present?
      Rails.logger.error("Erreur lors de la récupération des avis pour le dossier #{dossier.number}: #{result.errors.map(&:message).join(', ')}")
      return []
    end

    result.data&.dossier&.avis || []
  end

  def should_include_avis?(avis)
    # Appliquer les filtres si configurés
    return true unless @params[:filtres]

    @params[:filtres].all? do |filter_name, filter_value|
      case filter_name.to_s
      when 'expert_emails'
        Array(filter_value).include?(avis.expert&.email)
      when 'avec_reponse'
        filter_value ? avis.reponse.present? : avis.reponse.blank?
      when 'avec_question_fermee'
        filter_value ? avis.question_answer.present? : avis.question_answer.blank?
      else
        true
      end
    end
  end

  def flatten_avis(avis, baserow_table = nil)
    hash = {
      # Attributs directs de l'avis (accès Ruby snake_case)
      'id' => avis.id,
      'question' => avis.question,
      'reponse' => avis.reponse,
      'question_label' => avis.question_label,
      'question_answer' => avis.question_answer,
      'date_question' => avis.date_question,
      'date_reponse' => avis.date_reponse,

      # Expert avec notation pointée
      'expert.id' => avis.expert&.id,
      'expert.email' => avis.expert&.email,

      # Claimant avec notation pointée
      'claimant.id' => avis.claimant&.id,
      'claimant.email' => avis.claimant&.email
    }

    # Ajouter les données Baserow si disponibles
    if baserow_table && avis.expert&.email && @params[:baserow]
      baserow_row = baserow_table.search_normalized(
        @params[:baserow]['match_column'],
        avis.expert.email
      ).first

      if baserow_row
        # Fusionner toutes les colonnes Baserow au hash
        hash.merge!(baserow_row.transform_values { |v| v.is_a?(Hash) ? v['value'] : v })
      end
    end

    hash
  end

  def baserow_table
    return nil unless @params[:baserow]&.[]('table_id')

    # Mémoization pour éviter de réinstancier la table à chaque avis
    @baserow_table ||= begin
      config_name = @params[:baserow]['config_name']
      table_name = @params[:baserow]['table_name'] || 'Experts'

      Baserow::Config.table(
        @params[:baserow]['table_id'],
        config_name,
        table_name
      )
    end
  end

  def update_repetition_block(rows_data)
    return if rows_data.blank?

    # Allouer les blocs nécessaires dans l'annotation
    target_repetition = SetAnnotationValue.allocate_blocks(
      @dossier,
      instructeur_id,
      @params[:bloc_destination],
      rows_data.size
    )

    changed = populate_repetition_rows(rows_data, target_repetition)
    dossier_updated(@dossier) if changed
  end

  def populate_repetition_rows(rows_data, target_repetition)
    changed = false

    rows_data.each_with_index do |row_data, index|
      row_champs = target_repetition.rows[index]&.champs
      next unless row_champs

      changed = true if update_row_annotations(row_data, row_champs)
    end

    changed
  end

  def update_row_annotations(row_data, row_champs)
    changed = false

    row_data.each do |col_name, value|
      annotation = row_champs.find { |c| c.label == col_name }
      next unless annotation

      old_value = SetAnnotationValue.value_of(annotation)
      next if value == old_value

      SetAnnotationValue.raw_set_value(
        @dossier.id,
        instructeur_id,
        annotation.id,
        value
      )
      changed = true
    end

    changed
  end

  # Requête GraphQL pour récupérer les avis d'un dossier
  Query = MesDemarches::Client.parse <<-QUERY
    query DossierAvis($dossier: Int!) {
      dossier(number: $dossier) {
        avis {
          id
          question
          reponse
          questionLabel
          questionAnswer
          dateQuestion
          dateReponse
          expert {
            id
            email
          }
          claimant {
            id
            email
          }
        }
      }
    }
  QUERY
end
