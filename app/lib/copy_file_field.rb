# frozen_string_literal: true

class CopyFileField < FieldChecker
  OUTPUT_DIR = 'tmp/copy_file_field'
  def version
    super + 2
  end

  def initialize(params)
    super
    # OFFICE_PATH requis seulement si convert_to_pdf = true (défaut)
    convert = params.fetch(:convert_to_pdf, true)
    raise 'OFFICE_PATH not defined in .env file' if convert && ENV.fetch('OFFICE_PATH').blank?

    FileUtils.mkdir_p(OUTPUT_DIR)
  end

  def required_fields
    super + %i[champ_source champ_cible]
  end

  def authorized_fields
    super + %i[nom_fichier convert_to_pdf]
  end

  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    copy
  end

  def copy
    champs = file_fields(Array(params[:champ_source]))
    if champs.blank?
      Rails.logger.warn("Aucun champ source '#{@params[:champ_source]}' sur le dossier")
      return
    end

    convert = params.fetch(:convert_to_pdf, true)
    if convert
      copy_as_combined_pdf(champs)
    else
      copy_files_individually(champs)
    end
  end

  def copy_as_combined_pdf(champs)
    source_files = champs.flat_map(&:files)
    if source_files.blank?
      Rails.logger.warn("Aucun fichier à copier depuis '#{@params[:champ_source]}'")
      return
    end

    annotation = param_annotation(:champ_cible)
    raise "Unable to find annotation '#{params[:champ_cible]}' on dossier #{@dossier.number}" unless annotation.present?

    signature = sources_signature(source_files)
    if annotation.files&.any? { |f| f.filename.include?("-#{signature}.pdf") }
      Rails.logger.info("Sources déjà fusionnées dans '#{params[:champ_cible]}' (signature #{signature}), pas de reconversion")
      return
    end

    pdfs = champs.flat_map(&method(:download)).flat_map(&method(:to_pdf))
    if pdfs.blank?
      Rails.logger.warn("Aucun fichier à copier depuis '#{@params[:champ_source]}'")
      return
    end

    filename = target_filename(signature)
    Rails.logger.info("Joining files #{source_files.map(&:filename).join(',')} to #{filename}")
    combine_pdf(pdfs, filename) do |pdf_file|
      changed = SetAnnotationValue.set_piece_justificative_on_annotation(@dossier, instructeur_id_for(@demarche, @dossier), annotation, pdf_file.path, filename)
      dossier_updated(@dossier) if changed
    end
  end

  def copy_files_individually(champs)
    source_files = champs.flat_map(&:files)
    if source_files.blank?
      Rails.logger.warn("Aucun fichier à copier depuis '#{@params[:champ_source]}'")
      return
    end

    annotation = param_annotation(:champ_cible)
    raise "Unable to find annotation '#{params[:champ_cible]}' on dossier #{@dossier.number}" unless annotation.present?

    to_upload = source_files.reject { |src| annotation.files&.any? { |f| f.checksum == src.checksum } }
    if to_upload.empty?
      Rails.logger.info("Tous les fichiers sources sont déjà présents dans '#{params[:champ_cible]}', rien à copier")
      return
    end

    instructeur = instructeur_id_for(@demarche, @dossier)
    changed = false

    to_upload.each do |source_file|
      local_path = PieceJustificativeCache.get(source_file)
      SetAnnotationValue.set_piece_justificative_on_annotation(@dossier, instructeur, annotation, local_path, source_file.filename)
      Rails.logger.info("File #{source_file.filename} copied to #{params[:champ_cible]}")
      changed = true
    end

    dossier_updated(@dossier) if changed
  end

  private

  def delete(file)
    File.delete(file)
  end

  def target_filename(signature)
    timestamp = Time.zone.now.strftime('%Y-%m-%d %Hh%M')
    template = @params[:nom_fichier].presence || "#{@params[:champ_cible]} {horodatage}"
    "#{instanciate(template, { horodatage: timestamp })}-#{signature}.pdf"
  end

  def sources_signature(source_files)
    Digest::SHA1.hexdigest(source_files.map(&:checksum).sort.join('|'))[0..7]
  end

  def file_fields(field_names)
    field_names.flat_map { |name| object_field_values(@dossier, name, log_empty: false) }.filter { |champ| champ.__typename == 'PieceJustificativeChamp' }
  end

  def download(champ)
    return unless champ.__typename == 'PieceJustificativeChamp'

    champ.files.map { |f| PieceJustificativeCache.get(f) }
  end

  def to_pdf(file)
    if File.extname(file)&.downcase == '.pdf'
      pdf = Tempfile.new(['In-', '.pdf'], OUTPUT_DIR, binmode: true)
      IO.copy_stream(file, pdf)
      pdf.rewind
      pdf
    else
      convert_to_pdf(file)
    end
  end

  def convert_to_pdf(file)
    Rails.logger.info("Converting #{file} to pdf")
    stdout_str, stderr_str, status = Open3.capture3(ENV.fetch('OFFICE_PATH', nil), '--headless', '--convert-to', 'pdf', '--outdir', OUTPUT_DIR, file)
    if status != 0
      Rails.logger.error("Unable to convert #{file} to pdf\n#{stdout_str}#{stderr_str}")
      return
    end
    File.new(File.join(OUTPUT_DIR, File.basename(file).sub(/\.\w+$/, '.pdf')))
  end

  def combine_pdf(files, filename)
    File.open(File.join(OUTPUT_DIR, filename), 'wb') do |f|
      pdf = CombinePDF.new
      files.each { |file| pdf << CombinePDF.load(file.path, allow_optional_content: true) }
      pdf.save f
      files.each { |file| delete(file.path) }
      f.rewind
      yield f
    ensure
      f.close unless f.closed?
      File.delete(f)
    end
  end
end
