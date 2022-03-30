# frozen_string_literal: true

require 'set'

class Publipostage < FieldChecker
  OUTPUT_DIR = 'tmp/publipost'
  DATA_DIR = 'storage/publipost'
  BATCH_SIZE = 2.5 * 1024 * 1024

  def version
    super + 26 + @calculs.map(&:version).reduce(0, &:+)
  end

  def initialize(params)
    super
    @calculs = create_tasks
    @modele = @params[:modele]
    throw 'Modèle introuvable' unless File.exist?(@modele)
    throw 'OFFICE_PATH not defined in .env file' if ENV.fetch('OFFICE_PATH').blank?
    FileUtils.mkdir_p(OUTPUT_DIR)
    FileUtils.mkdir_p(DATA_DIR)
    @states = Set.new([*(@params[:etat_du_dossier] || 'en_instruction')])
  end

  def required_fields
    super + %i[champs message modele nom_fichier]
  end

  def authorized_fields
    super + %i[calculs dossier_cible etat_du_dossier champ_source nom_fichier_lot champ_force_publipost]
  end

  def process(demarche, dossier)
    super
    target = destination(dossier)
    return unless dossiers_have_right_state?(dossier, target)

    init_calculs

    pdf_paths = rows.filter_map do |row|
      compute_dynamic_fields(row)
      fields = get_fields(row, params[:champs])
      generate_doc(fields) unless same_document(fields)
    end
    return unless pdf_paths.present?

    combine(pdf_paths) do |pdf_path, batch_number|
      body = instanciate(@params[:message])
      timestamp = Time.zone.now.strftime('%Y-%m-%d %Hh%M')
      filename = build_filename(@params[:nom_fichier_lot] || @params[:nom_fichier],
                                { 'lot' => batch_number, 'horodatage' => timestamp }) + File.extname(pdf_path)
      SendMessage.send_with_file(target.id, demarche.instructeur, body, pdf_path, filename)
      annotation_updated_on(@dossier) # to prevent infinite check
    end
  end

  private

  def init_calculs
    @calculs.each do |calcul|
      calcul.demarche = @demarche
      calcul.dossier = @dossier
    end
  end

  def combine(pdf_paths)
    size = 0
    batch = 0
    pdf_batch = []
    pdf_paths.each do |path|
      file_size = File.size(path)
      if size + file_size > BATCH_SIZE
        batch += 1
        combine_batch(pdf_batch) { |combined_pdf| yield combined_pdf, batch }
        pdf_batch = []
        size = 0
      end
      size += file_size
      pdf_batch << path
    end
    combine_batch(pdf_batch) { |path| yield path, batch + 1 }
  end

  def combine_batch(pdf_batch)
    Tempfile.create(['publipost', '.pdf']) do |f|
      f.binmode
      pdf = CombinePDF.new
      pdf_batch.each { |path| pdf << CombinePDF.load(path) }
      pdf.save f
      pdf_batch.each { |path| File.delete(path) }
      f.rewind
      yield f
    end
  end

  def excel_to_rows(champ_source)
    PieceJustificativeCache.get(champ_source.file) do |file|
      next if File.extname(file) != '.xlsx'

      xlsx = Roo::Spreadsheet.open(file)
      sheet = xlsx.sheet(0)
      header_line = header_line(sheet)
      sheet_rows(header_line, sheet)
    ensure
      xlsx&.close
    end
  end

  MAPPING = { 'Nom de famille' => 'Nom' }.freeze

  def sheet_rows(header_line, sheet)
    rows = []
    headers = sheet.row(header_line)
    sheet.each_row_streaming do |row|
      data_row = row.size.positive? && row[1].coordinate[0] > header_line && row[1].value.present?
      rows << headers.map.with_index { |v, i| [MAPPING[v].presence || v, row[i].value] }.to_h if data_row
    end
    rows
  end

  def header_line(sheet)
    header_line = 0
    max = 0
    sheet.each_row_streaming do |row|
      cell = row.find { |c| c.value.nil? } || row.last
      next if cell.nil?

      count = cell.coordinate[1]
      count -= 1 if cell.value.nil?
      if count > max
        max = count
        header_line = cell.coordinate[0]
      end
    end
    header_line
  end

  def bloc_to_rows(champ_source)
    champs = champ_source.champs
    rows = []
    bloc = FieldList.new
    champs.each do |champ|
      if bloc[champ.label].present?
        rows << bloc
        bloc = FieldList.new
      end
      bloc << champ
    end
    rows << bloc
  end

  def rows
    champ_source_name = @params[:champ_source]
    return [@dossier] if champ_source_name.blank?

    fields(champ_source_name).map do |champ_source|
      case champ_source.__typename
      when 'PieceJustificativeChamp'
        excel_to_rows(champ_source)
      when 'RepetitionChamp'
        bloc_to_rows(champ_source)
      else
        []
      end
    end.reduce(&:+)
  end

  def dossiers_have_right_state?(dossier, target)
    return false unless @states.include?(dossier.state)

    (target == dossier || @states.include?(target.state))
  end

  def destination(dossier)
    field_name = @params[:dossier_cible]
    return dossier if field_name.blank?

    field = object_field_values(dossier, field_name)&.first
    Rails.logger.log('Le champ field_name est vide') if field.blank?
    field&.dossier || dossier
  end

  def same_document(fields)
    datafile = "#{DATA_DIR}/#{@dossier.number}/#{instanciate(@params[:nom_fichier], fields)}.yml"
    fields['#checksum'] = FileUpload.checksum(@modele)
    same = File.exist?(datafile) && YAML.load_file(datafile) == fields
    File.write(datafile, YAML.dump(fields)) unless same
    same
  end

  def instanciate(template, source = nil)
    template.gsub(/{[^{}]+}/) do |matched|
      variable = matched[1..-2]
      get_values_of(source, variable, variable, '').first
    end
  end

  def build_filename(template, source = nil)
    return 'document.pdf' if template.blank?

    instanciate(template, source).gsub(/[^- 0-9a-z\u00C0-\u017F.]/i, '_')
  end

  def generate_doc(row)
    basename = "#{OUTPUT_DIR}/#{build_filename(@params[:nom_fichier], row)}"
    docx = "#{basename}.docx"

    context = row.transform_keys { |k| k.gsub(/\s/, '_').gsub(/[()]/, '') }
    template = Sablon.template(File.expand_path(@modele))
    template.render_to_file docx, context
    stdout_str, stderr_str, status = Open3.capture3(ENV['OFFICE_PATH'], '--headless', '--convert-to', 'pdf', '--outdir', OUTPUT_DIR, docx)
    throw "Unable to convert #{docx} to pdf\n#{stdout_str}#{stderr_str}" if status != 0
    File.delete(docx)
    "#{basename}.pdf"
  end

  def get_fields(row, definitions)
    result = { 'Dossier' => @dossier.number }
    definitions.each do |definition|
      column, field, par_defaut = load_definition(definition)
      result[column] = [*get_values_of(row, column, field, par_defaut)].join(',')
    end
    result
  end

  # FieldList acts as a dossier allowing looking for champs
  class FieldList
    def initialize
      @champs = {}
    end

    def <<(champ)
      @champs[champ.label] = champ
    end

    def [](name)
      @champs[name]
    end

    def champs
      @champs.values
    end
  end

  def get_values_of(source, key, field, par_defaut = nil)
    return par_defaut unless field

    # from computed values
    value = @computed[key] if @computed.is_a? Hash
    return [*value] if value.present?

    # from excel source
    value = source[key] if source.is_a? Hash
    return [*value] if value.present?

    # from repetitive champs
    champs = object_field_values(source, field, log_empty: false) if source.is_a? FieldList
    return champs_to_values(champs) if champs.present?

    # from dossier champs
    champs = object_field_values(@dossier, field, log_empty: false)
    champs_to_values(champs).presence || [par_defaut]
  end

  def load_definition(param)
    if param.is_a?(Hash)
      par_defaut = param['par_defaut'] || ''
      field = param['champ']
      name = param['colonne']
    else
      field = param.to_s
      par_defaut = ''
    end
    name ||= last_name(field)
    [name, field, par_defaut]
  end

  def last_name(field)
    field[(field.rindex('.') || -1) + 1..]
  end

  def compute_dynamic_fields(row)
    @computed = compute_cells(row) if @calculs.present?
  end

  def compute_cells(row)
    @calculs.map { |task| task.process_row(row) }.reduce(&:merge)
  end

  def create_tasks
    taches = params[:calculs]
    return [] if taches.nil?

    InspectorTask.create_tasks(taches)
  end
end
