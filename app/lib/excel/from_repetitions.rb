# frozen_string_literal: true

module Excel
  class FromRepetitions < FieldChecker
    DATA_DIR = 'storage/from_repetitions'

    FIELD_TYPES = Set.new(%w[TextChamp IntegerNumberChamp DecimalNumberChamp CheckboxChamp CiviliteChamp
                             MultipleDropDownListChamp LinkedDropDownListChamp DateTimeChamp DateChamp NumeroDnChamp])

    def version
      super + 5
    end

    def required_fields
      super + %i[champ_cible modele]
    end

    def authorized_fields
      super + %i[champs_sources cellule_de_depart nom_fichier]
    end

    def initialize(params)
      super
      @champs_sources = Set.new(@params[:champs_sources] || [])
      @modele = @params[:modele]
      @cellule_de_depart = RubyXL::Reference.ref2ind(@params[:cellule_de_depart] || 'A1')
      raise "Modèle #{@modele} introuvable" unless File.exist?(@modele)
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)
      return if same_document(dossier)

      workbook = RubyXL::Parser.parse(@modele)
      dossier.champs.each do |champ|
        next unless champ.__typename == 'RepetitionChamp' && (@champs_sources.empty? || @champs_sources.include?(champ.label))

        worksheet = workbook[champ.label]

        champ.rows.each_with_index do |repetition, row_index|
          repetition.champs.each_with_index do |sous_champ, column_index|
            next unless FIELD_TYPES.include?(sous_champ.__typename)

            worksheet.add_cell(@cellule_de_depart[0] + row_index,
                               @cellule_de_depart[1] + column_index,
                               graphql_champ_value(sous_champ))
          end
        end
      end
      save_excel(workbook) { send_document(@demarche, @dossier, _1) }
      save_posted
    end

    def save_excel(workbook)
      Tempfile.create(['export_repetition', '.xlsx']) do |f|
        f.binmode
        workbook.write(f)
        f.rewind
        yield f
      end
    end

    def data_filename
      datadir = "#{DATA_DIR}/#{@dossier.number}"
      FileUtils.mkpath(datadir)
      datafilename = @params[:nom_fichier].gsub(/\s*\{^\}*\}/, '')
      "#{datadir}/#{datafilename}.yml"
    end

    def same_document(dossier)
      datafile = data_filename
      fields = repetition_to_array(dossier)
      fields['modele_checksum'] = FileUpload.checksum(@modele)
      @data = [datafile, fields]
      same = File.exist?(datafile) && YAML.load_file(datafile) == fields
      Rails.logger.info('Canceling Excel generation as input data coming from dossier is the same as before') if same
      same
    end

    def repetition_to_array(dossier)
      dossier.champs.each_with_object({}) do |champ, fields|
        next unless champ.__typename == 'RepetitionChamp' && (@champs_sources.empty? || @champs_sources.include?(champ.label))

        fields[champ.label] = champ.rows.each_with_object([]) do |repetition, table|
          table << repetition.champs.each_with_object([]) do |sous_champ, row|
            row << graphql_champ_value(sous_champ) if FIELD_TYPES.include?(sous_champ.__typename)
          end
        end
      end
    end

    def save_posted
      filename, fields = @data
      File.write(filename, YAML.dump(fields))
      @data = nil
    end

    def send_document(demarche, target, file)
      timestamp = Time.zone.now.strftime('%Y-%m-%d %Hh%M')
      filename = build_filename(@params[:nom_fichier] || @modele, { 'horodatage' => timestamp }) + File.extname(file)

      annotation = annotation(@params[:champ_cible])
      raise "Impossible de trouver l'annotation #{@params[:champ_cible]}" unless annotation.present?

      Rails.logger.info("Storing file #{filename} to private annotation #{annotation.label}")
      SetAnnotationValue.set_piece_justificative_on_annotation(target, instructeur_id_for(demarche, target), annotation, file, filename)
      dossier_updated(target)
    end

    def instanciate(template, source = nil)
      template.gsub(/{[^{}]+}/) do |matched|
        variable = matched[1..-2]
        get_values_of(source, variable, variable, '').first
      end
    end

    def get_values_of(source, key, field, par_defaut = nil)
      return par_defaut unless field

      # from excel source
      value = source[key] if source.is_a? Hash
      return [*value] if value.present?

      # from dossier champs
      champs = object_field_values(@dossier, field, log_empty: false)
      champs_to_values(champs).presence || [par_defaut]
    end

    def build_filename(template, source = nil)
      return 'document.pdf' if template.blank?

      instanciate(template, source).gsub(/[^- 0-9a-z\u00C0-\u017F.]/i, '_')
    end
  end
end
