# frozen_string_literal: true

class CopyFileField < FieldChecker
  OUTPUT_DIR = 'tmp/copy_file_field'
  def version
    super + 1
  end

  def initialize(params)
    super
    raise 'OFFICE_PATH not defined in .env file' if ENV.fetch('OFFICE_PATH').blank?

    FileUtils.mkdir_p(OUTPUT_DIR)
  end

  def required_fields
    super + %i[champ_source champ_cible]
  end

  def authorized_fields
    super + %i[nom_fichier]
  end

  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    copy
  end

  def copy
    champs = file_fields(Array(params[:champ_source]))
    pdfs = champs&.flat_map(&method(:download))&.flat_map(&method(:to_pdf))
    if pdfs.blank?
      Rails.logger.warn("Aucun champ source '#{@params[:champ_source]}' sur le dossier")
      return
    end

    filename = target_filename
    Rails.logger.info("Joining files #{champs.flat_map(&:files).flat_map(&:filename).join(',')} to #{filename}")
    combine_pdf(pdfs, filename) do |pdf_file|
      changed = SetAnnotationValue.set_piece_justificative(@dossier, instructeur_id_for(@demarche, @dossier), params[:champ_cible], pdf_file.path)
      dossier_updated(@dossier) if changed
    end
  end

  private

  def delete(file)
    File.delete(file)
  end

  def target_filename
    timestamp = Time.zone.now.strftime('%Y-%m-%d %Hh%M')
    template = @params[:nom_fichier].presence || "#{@params[:champ_cible]} {horodatage}"
    "#{instanciate(template, { horodatage: timestamp })}.pdf"
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
