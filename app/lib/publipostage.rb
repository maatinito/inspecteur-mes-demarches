# frozen_string_literal: true

require 'set'

class Publipostage < FieldChecker
  OUTPUT_DIR = 'tmp/publipost'
  DATA_DIR = 'storage/publipost'
  BATCH_SIZE = 2.5 * 1024 * 1024

  def version
    super + 38 + @calculs.map(&:version).reduce(0, &:+)
  end

  def initialize(params)
    super
    @calculs = create_tasks
    @modele = @params[:modele]
    @mails = @params[:destinataires]
    @mails = @mails.split(/\s*,\s*/) if @mails.is_a?(String)
    @champ_cible = @params[:champ_cible]
    @champ_source = @params[:champ_source]
    @generate_docx = @params[:type_de_document]&.match?(/\.?docx?/i)
    @if_field_set = @params[:si_presence_champ]
    @annexe_field = [*@params[:champ_annexe]]
    @publiposts = {}
    raise "Modèle #{@modele} introuvable" unless File.exist?(@modele)
    raise 'OFFICE_PATH not defined in .env file' if ENV.fetch('OFFICE_PATH').blank?

    FileUtils.mkdir_p(OUTPUT_DIR)
    FileUtils.mkdir_p(DATA_DIR)
    @states = Set.new([*(@params[:etat_du_dossier] || 'en_instruction')])
  end

  def required_fields
    super + %i[champs message modele nom_fichier]
  end

  def authorized_fields
    super + %i[calculs dossier_cible champ_source nom_fichier_lot champ_force_publipost destinataires champ_cible champ_annexe type_de_document si_presence_champ]
  end

  def must_check?(dossier)
    target = destination(dossier)
    dossiers_have_right_state?(dossier, target)
  end

  def process(demarche, dossier)
    super
    dossier_cible = destination(dossier)
    return unless dossiers_have_right_state?(dossier, dossier_cible)

    init_calculs

    paths = rows.filter_map do |row|
      next unless trigger_field_set(row)

      compute_dynamic_fields(row)
      fields = get_fields(row, params[:champs])
      next if same_document(fields)

      path = generate_doc(fields)
      send_if_target_field_is_in_current_row(demarche, dossier, row, path)
    end
    return unless paths.present?

    send_documents(demarche, dossier_cible, paths)
  end

  def normalized_fields(value)
    case value
    when Array
      value.map(&method(:normalized_fields))
    when Hash
      value.transform_values(&method(:normalized_fields))
    when String
      value.gsub(/&X-Amz.*/, '')
    else
      value
    end
  end

  def send_documents(demarche, dossier_cible, paths)
    annotation = dossier_annotations(dossier_cible, @champ_cible)&.first
    combine(paths) do |file, batch_number|
      send_document(demarche, dossier_cible, annotation, file, batch_number)
    end
    save_posted
  end

  def trigger_field_set(row)
    @if_field_set.blank? || get_values_of(row, @if_field_set, @if_field_set)&.find(&:present?)
  end

  def send_if_target_field_is_in_current_row(demarche, dossier, row, path)
    return path if @champ_source.blank? || @champ_cible.blank?

    annotation = dossier_fields(row, @champ_cible, warn_if_empty: false)&.first
    return path if annotation.blank?

    # store generated document on current repetition
    send_document(demarche, dossier, annotation, path, 1)
    save_posted
    nil
  end

  def send_document(demarche, target, annotation, file, batch_number)
    body = instanciate(@params[:message])
    timestamp = Time.zone.now.strftime('%Y-%m-%d %Hh%M')
    filename = build_filename(@params[:nom_fichier_lot] || @params[:nom_fichier],
                              { 'lot' => batch_number, 'horodatage' => timestamp }) + File.extname(file)

    if @mails.present?
      Rails.logger.info("Sending file #{filename} by mail to #{@mails}")
      send_mail(demarche, target, file, filename, body)
    end
    if annotation.present?
      Rails.logger.info("Storing file #{filename} to private annotation #{annotation.label}")
      SetAnnotationValue.set_piece_justificative_on_annotation(target, instructeur_id_for(demarche, dossier), annotation, file, filename)
    end
    unless @champ_cible.present? || @mails.present?
      Rails.logger.info("Sending file #{filename} to user using MD message system")
      SendMessage.send_with_file(target, instructeur_id_for(demarche, dossier), body, file, filename)
    end
    dossier_updated(@dossier) # to prevent infinite checks
  end

  def output_basename(row)
    "#{OUTPUT_DIR}/#{build_filename(@params[:nom_fichier], row)}"
  end

  def generate_docx(output_file, row)
    context = row.transform_keys { |k| k.gsub(/\s/, '_').gsub(/[()]/, '') }
                 .transform_values { |v| [*v].map(&:to_s).join(',') }

    template = Sablon.template(File.expand_path(@modele))
    template.render_to_file output_file, context
  end

  def rows_from_champs(champs)
    champs.map do |champ_source|
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

  def annexe_checksums
    annexe_champs.flat_map(&:file).map(&:checksum)
  end

  def add_annexes(result_path)
    champs = annexe_champs
    pdfs = champs.flat_map(&method(:download))
    if pdfs.present?
      Rails.logger.info("Adding annexes #{champs.flat_map(&:file).flat_map(&:filename).join(',')}")
      combine_pdf([result_path, *pdfs]) do |file|
        IO.copy_stream(file, result_path)
      end
    end
    result_path
  end

  def annexe_champs
    @annexe_field.flat_map { |name| object_field_values(@dossier, name, log_empty: false) }
                 .filter { |champ| champ.__typename == 'PieceJustificativeChamp' && champ&.file&.filename&.end_with?('.pdf') }
  end

  def download(champ)
    PieceJustificativeCache.get(champ.file) if champ.__typename == 'PieceJustificativeChamp'
  end

  def data_filename(fields)
    datadir = "#{DATA_DIR}/#{@dossier.number}"
    FileUtils.mkpath(datadir)
    datafilename = @params[:nom_fichier].gsub(/\s*\{(horodatage|lot)\}/, '')
    "#{datadir}/#{instanciate(datafilename, fields)}.yml"
  end

  private

  def send_mail(demarche, dossier, file, filename, message)
    params = {
      subject: demarche.libelle,
      demarche: demarche.id,
      dossier: dossier.number,
      message:,
      filename:,
      file: File.read(file, mode: 'rb'),
      recipients: @mails
    }
    NotificationMailer.with(params).notify_user.deliver_later
  end

  def init_calculs
    @calculs.each do |calcul|
      calcul.demarche = @demarche
      calcul.dossier = @dossier
    end
  end

  def combine(paths, batch_size = BATCH_SIZE)
    size = 0
    batch = 0
    batch_files = []
    paths.each do |path|
      file_size = File.size(path)
      if size + file_size > batch_size && batch_files.size.positive?
        batch += 1
        combine_batch(batch_files) { |combined_pdf| yield combined_pdf, batch }
        batch_files = []
        size = 0
      end
      size += file_size
      batch_files << path
    end
    combine_batch(batch_files) { |path| yield path, batch + 1 }
  end

  def combine_batch(files, &)
    if files.size == 1
      combine_one(files, &)
    elsif @generate_docx
      combine_zip(files, &)
    else
      combine_pdf(files, &)
    end
  end

  def excel_to_rows(champ_source)
    return nil if champ_source.file.blank?
    return champ_source.file.url if File.extname(champ_source.file.filename) != '.xlsx'

    PieceJustificativeCache.get(champ_source.file) do |file|
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
    return [@dossier] if @champ_source.blank?

    rows_from_champs(fields(@champ_source).presence || annotations(@champ_source))
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
    datafile = data_filename(fields)
    stable_fields = normalized_fields(fields)
    stable_fields['#checksum'] = FileUpload.checksum(@modele)
    stable_fields['#annexes'] = annexe_checksums if @annexe_field.present?

    same = File.exist?(datafile) && YAML.load_file(datafile) == stable_fields
    if same
      Rails.logger.info('Canceling publipost as input data coming from dossier is the same as before')
    else
      @publiposts[datafile] = stable_fields
    end
    same
  end

  def save_posted
    @publiposts.reject! do |filename, fields|
      File.write(filename, YAML.dump(fields))
      true
    end
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
    basename = output_basename(row)
    docx = "#{basename}.docx"
    Rails.logger.info("Generating docx template #{@modele}")
    generate_docx(docx, row)

    return docx if @generate_docx

    Rails.logger.info('Converting docx to pdf')
    stdout_str, stderr_str, status = Open3.capture3(ENV.fetch('OFFICE_PATH', nil), '--headless', '--convert-to', 'pdf', '--outdir', OUTPUT_DIR, docx)
    raise "Unable to convert #{docx} to pdf\n#{stdout_str}#{stderr_str}" if status != 0

    delete(docx)

    add_annexes("#{basename}.pdf")
  end

  def get_fields(row, definitions)
    result = { 'Dossier' => @dossier.number }
    definitions.each do |definition|
      column, field, par_defaut = load_definition(definition)
      result[column] = get_values_of(row, column, field, par_defaut)
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
      par_defaut = param['par défaut'] || ''
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

  def combine_one(files, &)
    File.open(files[0], 'r', &)
  ensure
    delete(files[0])
  end

  def delete(file)
    File.delete(file)
  end

  def combine_pdf(files)
    Tempfile.create(['publipost', '.pdf']) do |f|
      f.binmode
      pdf = CombinePDF.new
      files.each { |path| pdf << CombinePDF.load(path) }
      pdf.save f
      files.each { |path| delete(path) }
      f.rewind
      yield f
    end
  end

  def combine_zip(files)
    Tempfile.create(['publipost', '.zip']) do |f|
      Zip::File.open(f, create: true) do |zipfile|
        files.each do |filename|
          zipfile.add(filename, filename)
        end
      end
      files.each { |path| delete(path) }
      yield f
    end
  end
end
