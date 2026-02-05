# frozen_string_literal: true

module Daf
  class CopyOrder < FieldChecker
    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .tiff .tif .svg .webp].freeze
    OUTPUT_DIR = 'tmp/copy_order'

    def version
      super + 2
    end

    def required_fields
      # champ_destination n'est plus requis car on peut utiliser champs_destination à la place
      super + %i[champ_source bloc_destination]
    end

    def authorized_fields
      super + %i[champ_destination valeur champs_destination convert_to_pdf]
    end

    def initialize(params)
      super
      validate_configuration

      # OFFICE_PATH requis seulement si convert_to_pdf = true
      convert = params.fetch(:convert_to_pdf, false)
      raise 'OFFICE_PATH not defined in .env file but convert_to_pdf is enabled' if convert && ENV['OFFICE_PATH'].blank?

      FileUtils.mkdir_p(OUTPUT_DIR)
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      create_orders(orders)
    end

    def create_orders(orders)
      return if orders.blank?

      # Allouer les lignes dans le bloc de répétition destination
      target_repetition = SetAnnotationValue.allocate_blocks(
        @dossier,
        @demarche.instructeur,
        @params[:bloc_destination],
        orders.size
      )

      changed = false
      orders.each_with_index do |row_data, index|
        dest_row = target_repetition.rows[index]
        next unless dest_row

        # Définir tous les champs configurés pour cette ligne
        row_changed = set_destination_fields(dest_row, row_data)
        changed ||= row_changed
      end

      dossier_updated(@dossier) if changed
    end

    private

    def validate_configuration
      return if @params[:champs_destination].present? || @params[:champ_destination].present?

      raise "Configuration invalide: au moins 'champ_destination' ou 'champs_destination' doit être spécifié"
    end

    def fields_configuration
      if @params[:champs_destination].present?
        # Nouvelle syntaxe: retourner tel quel
        @params[:champs_destination]
      elsif @params[:champ_destination].present?
        # Ancienne syntaxe: convertir au nouveau format
        { @params[:champ_destination] => @params[:valeur] }
      else
        raise "Configuration invalide: au moins 'champ_destination' ou 'champs_destination' doit être spécifié"
      end
    end

    def process_text_value(row, config)
      if config.nil?
        # Pas de template: joindre toutes les valeurs (compatibilité arrière)
        champs_to_values(row.champs).join(', ')
      elsif config.include?('{')
        # Template avec syntaxe mustache
        instanciate(config, row)
      else
        # Référence directe à un champ
        field_values = object_field_values(row, config, log_empty: false)
        champs_to_values(field_values).join(', ')
      end
    end

    def process_file_field(row, field_name)
      # Trouver le champ source dans la row
      source_champ = row.champs.find { |c| c.label == field_name }
      return [] unless source_champ&.__typename == 'PieceJustificativeChamp'
      return [] unless source_champ.files.present?

      # Retourner les objets GraphQL (avec checksum et filename) pour éviter
      # de télécharger les fichiers avant de vérifier s'ils existent déjà
      source_champ.files
    end

    def image_file_by_name?(filename)
      ext = File.extname(filename).downcase
      IMAGE_EXTENSIONS.include?(ext)
    end

    def image_file?(path)
      ext = File.extname(path).downcase
      IMAGE_EXTENSIONS.include?(ext)
    end

    def convert_file_to_pdf(file_path)
      # Si déjà PDF, retourner tel quel
      return file_path if File.extname(file_path).downcase == '.pdf'

      # Vérifier que OFFICE_PATH est défini
      if ENV['OFFICE_PATH'].blank?
        Rails.logger.error("OFFICE_PATH non défini, impossible de convertir #{file_path}")
        return nil
      end

      Rails.logger.info("Conversion de #{file_path} en PDF")

      stdout_str, stderr_str, status = Open3.capture3(
        ENV.fetch('OFFICE_PATH'),
        '--headless',
        '--convert-to', 'pdf',
        '--outdir', OUTPUT_DIR,
        file_path
      )

      if status != 0
        Rails.logger.error("Impossible de convertir #{file_path} en PDF\n#{stdout_str}#{stderr_str}")
        return nil
      end

      File.join(OUTPUT_DIR, File.basename(file_path).sub(/\.\w+$/, '.pdf'))
    rescue StandardError => e
      Rails.logger.error("Erreur lors de la conversion de #{file_path}: #{e.message}")
      nil
    end

    def detect_field_type(row, config)
      # Stratégie 1: Référence directe à un champ (pas de template)
      if !config.nil? && !config.include?('{')
        # C'est un nom de champ direct - vérifier le type du champ source
        source_champ = row.champs.find { |c| c.label == config }
        return :file if source_champ&.__typename == 'PieceJustificativeChamp'
        return :text if source_champ
      end

      # Stratégie 2: Template ou nil - supposer texte
      :text
    end

    def extract_row_data(row)
      config = fields_configuration
      result = {}

      config.each do |dest_field, source_config|
        field_type = detect_field_type(row, source_config)

        result[dest_field] = case field_type
                             when :text
                               process_text_value(row, source_config)
                             when :file
                               process_file_field(row, source_config)
                             end
      end

      result
    end

    def set_destination_fields(dest_row, row_data)
      changed = false

      row_data.each do |field_name, value|
        next if value.blank?

        annotation = dest_row.champs.find { |c| c.label == field_name }
        unless annotation
          Rails.logger.warn("Champ destination '#{field_name}' introuvable sur le dossier #{@dossier.number}")
          next
        end

        field_changed = if value.is_a?(Array)
                          # Champ fichier (array d'objets GraphQL avec checksum et filename)
                          set_file_field(annotation, value)
                        else
                          # Champ texte
                          set_text_field(annotation, value)
                        end

        changed ||= field_changed
      end

      changed
    end

    def set_text_field(annotation, value)
      current_value = SetAnnotationValue.value_of(annotation)
      return false if current_value == value

      SetAnnotationValue.raw_set_value(
        @dossier.id,
        @demarche.instructeur,
        annotation.id,
        value
      )
      Rails.logger.info("Champ '#{annotation.label}' mis à jour avec '#{value}'")
      true
    rescue StandardError => e
      Rails.logger.error("Erreur lors de la mise à jour du champ texte '#{annotation.label}': #{e.message}")
      false
    end

    # Ces méthodes retournent un booléen de statut (comme save/update), pas un prédicat
    # rubocop:disable Naming/PredicateMethod
    def set_file_field(annotation, source_files)
      return false if source_files.blank?

      files_uploaded = 0

      source_files.each do |source_file|
        uploaded = upload_file_if_needed(annotation, source_file)
        files_uploaded += 1 if uploaded
      end

      files_uploaded.positive?
    end

    def upload_file_if_needed(annotation, source_file)
      filename = source_file.filename
      convert = params.fetch(:convert_to_pdf, false)

      if convert && !pdf_file_by_name?(filename)
        # Conversion PDF demandée et fichier n'est pas déjà un PDF
        upload_converted_if_needed(annotation, source_file)
      else
        # Copie sans conversion (défaut)
        upload_original_if_needed(annotation, source_file)
      end
    rescue StandardError => e
      Rails.logger.error("Erreur lors du traitement du fichier #{filename} vers #{annotation.label}: #{e.message}")
      false
    end

    def pdf_file_by_name?(filename)
      File.extname(filename).downcase == '.pdf'
    end

    def upload_original_if_needed(annotation, source_file)
      filename = source_file.filename
      source_checksum = source_file.checksum

      # Vérifier le checksum source AVANT de télécharger
      same_file = annotation.files&.find { |f| f.checksum == source_checksum }

      if same_file
        Rails.logger.info("Fichier #{filename} déjà présent dans #{annotation.label} (même checksum), pas d'upload")
        return false
      end

      # Télécharger et uploader le fichier tel quel
      local_path = PieceJustificativeCache.get(source_file)
      SetAnnotationValue.set_piece_justificative_on_annotation(
        @dossier,
        @demarche.instructeur,
        annotation,
        local_path,
        filename
      )
      Rails.logger.info("Fichier #{filename} uploadé avec succès vers #{annotation.label}")
      true
    end

    def upload_converted_if_needed(annotation, source_file)
      filename = source_file.filename
      source_checksum = source_file.checksum

      # Nom du fichier converti contient le checksum source pour éviter les reconversions
      base_name = File.basename(filename, '.*')
      converted_filename = "#{base_name}-#{source_checksum[0..7]}.pdf"

      # Vérifier si on a déjà converti CE fichier source (par le nom de fichier)
      same_source = annotation.files&.find { |f| f.filename == converted_filename }

      if same_source
        Rails.logger.info("Source #{filename} déjà converti dans #{annotation.label} (#{converted_filename}), pas de reconversion")
        return false
      end

      # Télécharger et convertir
      local_path = PieceJustificativeCache.get(source_file)
      converted_path = convert_file_to_pdf(local_path)

      return false unless converted_path

      # Uploader avec le nom contenant le checksum source
      SetAnnotationValue.set_piece_justificative_on_annotation(
        @dossier,
        @demarche.instructeur,
        annotation,
        converted_path,
        converted_filename
      )
      Rails.logger.info("Fichier #{filename} converti et uploadé vers #{annotation.label} comme #{converted_filename}")
      true
    end
    # rubocop:enable Naming/PredicateMethod

    def orders
      rows = param_field(:champ_source)&.rows
      return [] if rows.blank?

      rows.map { |row| extract_row_data(row) }
    end
  end
end
