# frozen_string_literal: true

module MesDemarchesToGrist
  # Synchronise les avis d'un dossier vers la table Grist des avis (construite
  # par SchemaBuilders::AvisBuilder, nommée Avis_<n° démarche>).
  #
  # Parité avec MesDemarchesToBaserow::AvisSyncer :
  # - upsert par id GraphQL de l'avis (colonne Avis, clé stable) ;
  # - rattachement à la ligne du dossier (colonne Dossier, Ref) ;
  # - suppression des avis disparus du dossier (option supprimer_orphelins) ;
  # - colonnes appariées par libellé, colonnes absentes ou formules ignorées.
  # « Date réponse » n'est renseignée que pour un avis répondu : l'API la remplit
  # avec la date de dernière modification de l'avis (cf. AvisFetcher.repondu?).
  class AvisSyncer
    AVIS_LABEL = 'Avis'
    DOSSIER_LABEL = 'Dossier'

    def initialize(doc_id:, table_id:, main_table_id:, options:, token_config: nil)
      @doc_id = doc_id
      @table_id = table_id
      @main_table_id = main_table_id
      @options = options || {}
      @token_config = token_config
    end

    def sync(dossier_number, main_record_id)
      return unless main_record_id && valid_structure?

      avis_list = MesDemarches::AvisFetcher.fetch(dossier_number)
      existing = table.find_by(@dossier_col, main_record_id)
      existing_by_avis = existing.index_by { |record| record.dig('fields', @avis_col).to_s }

      records = avis_list.map do |avis|
        fields = convert(avis_values(avis, existing_by_avis[avis.id.to_s]))
        fields[@dossier_col] = main_record_id
        { require: { @avis_col => avis.id.to_s }, fields: fields }
      end
      table.upsert_records(records) if records.any?
      Rails.logger.info "GristSync.avis: #{records.size} avis synchronisé(s) pour le dossier #{dossier_number}"

      delete_orphans(existing, avis_list.to_set { |a| a.id.to_s }, dossier_number) if supprimer_orphelins?
    end

    private

    def table
      @table ||= Grist::Config.table(@doc_id, @table_id, @token_config)
    end

    def columns_by_label
      @columns_by_label ||= table.columns.values.index_by { |meta| meta[:label] }
    end

    # Colonnes Avis et Dossier présentes, Dossier pointant vers la table
    # principale de la démarche (un document peut en réunir plusieurs).
    def valid_structure?
      return @valid if defined?(@valid)

      @avis_col = columns_by_label.dig(AVIS_LABEL, :id)
      dossier = columns_by_label[DOSSIER_LABEL]
      @dossier_col = dossier&.dig(:id)
      @valid = @avis_col.present? && dossier.present? && dossier[:type] == "Ref:#{@main_table_id}"
      unless @valid
        Rails.logger.warn "GristSync.avis: table #{@table_id} ignorée — colonnes Avis et Dossier (Ref:#{@main_table_id}) " \
                          "attendues, Dossier de type #{dossier&.dig(:type).inspect}"
      end
      @valid
    end

    # Valeurs par libellé de colonne.
    def avis_values(avis, existing_record)
      repondu = MesDemarches::AvisFetcher.repondu?(avis)
      {
        'Question' => avis.question,
        'Réponse' => avis.reponse,
        'Libellé question' => avis.question_label,
        'Réponse fermée' => avis.question_answer,
        'Date question' => avis.date_question,
        'Date réponse' => (avis.date_reponse if repondu),
        'Email expert' => avis.expert&.email,
        'Email demandeur' => avis.claimant&.email,
        'Pièces jointes' => attachments(avis, existing_record)
      }
    end

    # Libellés → ids de colonnes inscriptibles, valeurs mises au format Grist.
    # Pièces jointes absentes : la cellule n'est pas touchée (comme Baserow).
    def convert(values)
      values.each_with_object({}) do |(label, value), fields|
        meta = columns_by_label[label]
        next unless meta
        next if meta[:isFormula] && meta[:formula].present?
        next if meta[:type] == 'Attachments' && value.nil?

        fields[meta[:id]] = format_value(value, meta[:type])
      end
    end

    def format_value(value, type)
      return nil if value.nil?

      if type.to_s.start_with?('DateTime')
        DateTime.parse(value.to_s).to_time.to_i
      elsif type == 'Date'
        Date.parse(value.to_s).to_time.to_i
      else
        value
      end
    rescue ArgumentError
      nil
    end

    # Pièces jointes au format Grist ["L", id…] : un fichier déjà présent (même
    # nom, même taille) garde son attachment, les nouveaux sont téléversés.
    def attachments(avis, existing_record)
      files = Array(avis.attachments)
      return nil if files.empty?

      deja = existing_attachments(existing_record)
      ids = files.filter_map do |file|
        found = deja.find { |att| att[:name] == file.filename.to_s.strip && att[:size] == file.byte_size }
        found ? found[:id] : uploader.download_and_upload(file.url, file.filename.to_s.strip)
      end
      ids.empty? ? nil : ['L'] + ids
    end

    def existing_attachments(record)
      col = columns_by_label.dig('Pièces jointes', :id)
      value = record&.dig('fields', col)
      return [] unless value.is_a?(Array) && value.first == 'L'

      value.drop(1).filter_map do |id|
        info = Grist::Config.client(@token_config).get_attachment_metadata(@doc_id, id)
        { id: id, name: info['fileName'], size: info['fileSize'] }
      rescue Grist::APIError => e
        Rails.logger.warn "GristSync.avis: métadonnées de la pièce jointe #{id} illisibles : #{e.message}"
        nil
      end
    end

    def uploader
      @uploader ||= Grist::FileUploader.new(Grist::Config.client(@token_config), @doc_id)
    end

    def delete_orphans(existing, current_ids, dossier_number)
      orphan_ids = existing.reject { |record| current_ids.include?(record.dig('fields', @avis_col).to_s) }.map { |r| r['id'] }
      return if orphan_ids.empty?

      table.delete_records(orphan_ids)
      Rails.logger.info "GristSync.avis: #{orphan_ids.size} avis disparu(s) supprimé(s) (dossier #{dossier_number})"
    end

    def supprimer_orphelins?
      @options.key?('supprimer_orphelins') ? @options['supprimer_orphelins'] : true
    end
  end
end
