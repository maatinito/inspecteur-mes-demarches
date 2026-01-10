# frozen_string_literal: true

class Publipostage < FieldChecker
  OUTPUT_DIR = 'tmp/publipost'
  BATCH_SIZE = 2.5 * 1024 * 1024

  def version
    super + 38 + @calculs.map(&:version).reduce(0, &:+)
  end

  def initialize(params)
    super
    @calculs = create_tasks
    @template_pattern = @params[:modele]
    @mails = @params[:destinataires]
    @mails = @mails.split(/\s*,\s*/) if @mails.is_a?(String)
    @champ_cible = @params[:champ_cible]
    @champ_source = @params[:champ_source]
    @generate_docx = @params[:type_de_document]&.match?(/\.?docx?/i)
    @if_field_set = @params[:si_presence_champ]
    @annexe_field = [*@params[:champ_annexe]]
    @publiposts = {}
    @sender = @params[:expediteur]
    raise 'OFFICE_PATH not defined in .env file' if ENV.fetch('OFFICE_PATH').blank?

    FileUtils.mkdir_p(OUTPUT_DIR)
    @states = Set.new([*(@params[:etat_du_dossier] || 'en_instruction')])
  end

  def required_fields
    super + %i[champs message modele nom_fichier]
  end

  def authorized_fields
    super + %i[calculs expediteur dossier_cible champ_source nom_fichier_lot champ_force_publipost destinataires champ_cible champ_annexe type_de_document si_presence_champ]
  end

  def must_check?(dossier)
    target = destination(dossier)
    dossiers_have_right_state?(dossier, target)
  end

  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    dossier_cible = destination(dossier)
    unless dossiers_have_right_state?(dossier, dossier_cible)
      Rails.logger.info("Dossier ignored as state #{dossier.state} is not in required states #{@states}")
      return
    end

    init_calculs

    paths = rows.filter_map.with_index do |row, i|
      next unless trigger_field_set(row)

      fields = get_fields(row, params[:champs], i)
      compute_dynamic_fields(row, fields)
      @template = instanciate(@template_pattern)

      next if same_document(fields)

      # Ajouter les variables volatiles après la vérification same_document
      add_volatile_fields(fields)

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

  def deep_transform_keys(value, &)
    case value
    when Hash
      value.each_with_object({}) do |(key, value), result|
        new_key = yield(key)
        new_value = deep_transform_keys(value, &)
        result[new_key] = new_value
      end
    when Array
      value.map { |v| deep_transform_keys(v, &) }
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
    @if_field_set.blank? || get_values_of(row, @if_field_set)&.find(&:present?)
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
                              { lot: batch_number, horodatage: timestamp }) + File.extname(file)

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
      SendMessage.deliver_message_with_file(target, sender_id(demarche.id) || instructeur_id_for(demarche, dossier), body, file, filename)
    end
    dossier_updated(@dossier)
  end

  def output_basename(row)
    "#{OUTPUT_DIR}/#{build_filename(@params[:nom_fichier], row)}"
  end

  def generate_docx(output_file, row)
    context = row.transform_keys { |k| k.gsub(/\s/, '_').gsub(/[()]/, '') }
                 .transform_values { |v| [*v].map(&:to_s).join(', ') }

    template = Sablon.template(VerificationService.file_manager.filepath(@template))
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
    annexe_champs.flat_map(&:files).map(&:checksum)
  end

  def add_annexes(result_path)
    champs = annexe_champs
    pdfs = champs&.flat_map(&method(:download))&.flat_map(&method(:to_pdf))
    if pdfs.present?
      Rails.logger.info("Adding annexes #{champs.flat_map(&:file).flat_map(&:filename).join(',')}")
      combine_pdf([result_path, *pdfs]) do |file|
        IO.copy_stream(file, result_path)
      end
    end
    result_path
  end

  def to_pdf(file)
    return file if File.extname(file)&.downcase == '.pdf'

    convert_to_pdf(file)
  end

  def annexe_champs
    @annexe_field.flat_map { |name| object_field_values(@dossier, name, log_empty: false) }
                 .filter { |champ| champ.__typename == 'PieceJustificativeChamp' }
  end

  def download(champ)
    return unless champ.__typename == 'PieceJustificativeChamp'

    champ.files.map { |f| PieceJustificativeCache.get(f) }
  end

  # def data_filename(fields)
  #   datadir = "#{DATA_DIR}/#{@dossier.number}"
  #   FileUtils.mkpath(datadir)
  #   datafilename = @params[:nom_fichier].gsub(/\s*\{(horodatage|lot)\}/, '')
  #   "#{datadir}/#{instanciate(datafilename, fields)}.yml"
  # end

  def label(fields)
    template = @params[:nom_fichier].gsub(/\s*\{(horodatage|lot)\}/, '')
    instanciate(template, fields)
  end

  private

  def add_volatile_fields(fields)
    # Variables volatiles qui ne doivent pas être stockées dans DossierData
    # pour éviter de redéclencher le publipostage à chaque changement
    fields['Aujourd\'hui'] = Time.zone.today.strftime('%d/%m/%Y')
  end

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
    return nil if champ_source.files.blank?

    champ_file = champ_source.files.last
    file_ext = File.extname(champ_file.filename)
    return [] unless ['.xlsx', '.csv'].include?(file_ext)

    PieceJustificativeCache.get(champ_file) do |file|
      case file_ext
      when '.xlsx'
        xlsx = Roo::Spreadsheet.open(file)
        sheet = xlsx.sheet(0)
        header_line = header_line(sheet)
        sheet_rows(header_line, sheet)
      when '.csv'
        Roo::CSV.new(file).parse(headers: true)[1..].each do |row|
          row.transform_values! do |v|
            if v.match(/^\d+$/)
              v.to_i
            else
              v.match(/^[\d.]+$/) ? v.to_f : v
            end
          end
        end
      end
    ensure
      xlsx&.close
    end
  end

  def sheet_rows(header_line, sheet)
    rows = []
    headers = sheet.row(header_line)
    sheet.each_row_streaming(pad_cells: true, offset: header_line) do |row|
      break unless row.any? { it&.value.present? }

      rows << headers.each_with_object({}).with_index do |(k, h), i|
        value = row[i]&.value
        value = value.gsub('_x000D_', '') if value.is_a?(String)
        h[k] = value || ''
      end
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
    champ_source.rows.map do |row|
      FieldList.new(row.champs)
    end
  end

  def rows
    return [@dossier] if @champ_source.blank?

    rows_from_champs(fields(@champ_source).presence || annotations(@champ_source))
  end

  def dossiers_have_right_state?(dossier, target)
    return false unless @states.include?(dossier.state)

    target == dossier || @states.include?(target.state)
  end

  def destination(dossier)
    field_name = @params[:dossier_cible]
    return dossier if field_name.blank?

    field = object_field_values(dossier, field_name)&.first
    Rails.logger.log('Le champ field_name est vide') if field.blank?
    field&.dossier || dossier
  end

  def same_document(fields)
    stable_fields = normalized_fields(deep_transform_keys(fields, &:to_s))
    # publipost no longer generate new document when docx template is modified
    # Else this may generate bills or official documents each time the template is modified.
    # stable_fields['#checksum'] = FileUpload.checksum(VerificationService.file_manager.filepath(@template))
    stable_fields['#annexes'] = annexe_checksums if @annexe_field.present?

    label = label(fields)
    data = DossierData.find_by_folder_and_label(@dossier.number, label)
    # migrate data to ignore #checksum
    data.save if data.present? && data.data.delete('#checksum').present?

    same = data.present? && data.data == stable_fields
    if same
      Rails.logger.info('Canceling publipost as input data coming from dossier is the same as before')
    else
      @publiposts[label] = stable_fields
    end
    same
  end

  def save_posted
    @publiposts.reject! do |label, fields|
      # File.write(filename, YAML.dump(fields))
      data = DossierData.find_or_initialize_by(dossier: @dossier.number, label:)
      data.update!(data: fields)
      true
    end
  end

  def build_filename(template, source = nil)
    return 'document.pdf' if template.blank?

    instanciate(template, source).gsub(/[^- 0-9a-z\u00C0-\u017F.]/i, '_')
  end

  def generate_doc(row)
    basename = output_basename(row)
    docx = "#{basename}.docx"
    Rails.logger.info("Generating docx with template #{@template}")
    generate_docx(docx, row)

    return docx if @generate_docx

    pdf = convert_to_pdf(docx)

    delete(docx)

    add_annexes(pdf)
  end

  def convert_to_pdf(file)
    Rails.logger.info("Converting #{file} to pdf")
    stdout_str, stderr_str, status = Open3.capture3(ENV.fetch('OFFICE_PATH', nil), '--headless', '--convert-to', 'pdf', '--outdir', OUTPUT_DIR, file)
    if status != 0
      Rails.logger.error("Unable to convert #{file} to pdf\n#{stdout_str}#{stderr_str}")
      return
    end
    File.join(OUTPUT_DIR, File.basename(file).sub(/\.\w+$/, '.pdf'))
  end

  def get_fields(row, definitions, index)
    result = { 'Dossier' => @dossier.number, '#index' => index + 1 }
    definitions.each do |definition|
      column, field, par_defaut = load_definition(definition)
      value = get_values_of(row, field, par_defaut)
      expand_hash_into_result(result, column, value)
    end
    result
  end

  # Expands a value into the result hash, handling expanded fields
  # If value is a Hash with "" and ".xxx" keys (expanded field),
  # it transforms them into "prefix" and "prefix.xxx" keys
  def expand_hash_into_result(result, prefix, value)
    if value.is_a?(Hash) && value.key?('')
      # C'est un champ expansé avec la convention "" et ".xxx"
      value.each do |key, val|
        new_key = key.empty? ? prefix : "#{prefix}#{key}"
        result[new_key] = val
      end
    else
      # Comportement classique
      result[prefix] = value
    end
  end

  # FieldList acts as a dossier allowing looking for champs
  class FieldList
    def initialize(champs = [])
      @champs = champs.index_by(&:label)
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

  def get_values_of(source, field, par_defaut = nil)
    return par_defaut unless field

    # from computed values
    value = @computed[field] if @computed.is_a? Hash
    return [*value] if value.present?

    super
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
    field[((field.rindex('.') || -1) + 1)..]
  end

  def compute_dynamic_fields(row, fields)
    return unless @calculs.present?

    @calculs.each { |task| task.process_row(row, fields) }
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
      files.each { |path| pdf << CombinePDF.load(path, allow_optional_content: true) }
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

  def sender_id(demarche_id)
    return nil unless @sender

    @sender_id ||= DemarcheActions.get_graphql_demarche(demarche_id).groupe_instructeurs.flat_map(&:instructeurs).find { |i| i.email == @sender }&.id
  end
end
