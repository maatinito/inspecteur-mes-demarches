# frozen_string_literal: true

class PieceJustificativeCache
  DIR = FileUtils.mkpath(Rails.env.test? ? 'tmp/pjs' : 'storage/pjs').first
  SIZE = 50 * 1024 * 1024

  class << self
    def get(md_file)
      pathname = pathname(md_file.filename, md_file.checksum)
      unless pathname.size?
        File.open(pathname, 'wb') do |f|
          IO.copy_stream(URI.parse(md_file.url).open, f)
          f.close
        end
        maintenance
      end
      if block_given?
        yield pathname.to_s
      else
        pathname.to_s
      end
    end

    # Génère un fichier si absent du cache, sinon le retourne
    # Le block doit retourner le contenu binaire à écrire
    #
    # Exemple :
    #   path = PieceJustificativeCache.get_or_generate('qrcode.png', checksum) do
    #     RQRCode::QRCode.new(data).as_png(size: 300).to_s
    #   end
    def get_or_generate(filename, checksum)
      pathname = pathname(filename, checksum)
      unless pathname.size?
        content = yield # Le block génère le contenu
        File.binwrite(pathname, content)
        maintenance
      end
      pathname.to_s
    end

    def put(src)
      dst = pathname(src, FileUpload.checksum(src))
      FileUtils.cp(src, dst)
      maintenance
    end

    def maintenance
      files = Dir.glob("#{DIR}/*").select { |f| File.file?(f) }.sort_by { |f| File.mtime(f) }
      size = files.map { |f| File.size(f) }.reduce(&:+)
      while size > SIZE && files.size > 2 # always keep at least last file
        file = files.first
        size -= File.size(file)
        File.delete(file)
        files.shift
      end
    end

    def clean
      Dir.glob("#{DIR}/*").select { |f| File.file?(f) }.each { |f| File.delete(f) }
    end

    private

    def pathname(src, checksum)
      checksum = checksum.gsub(%r{[/\\]}, '_')
      filename = checksum + File.extname(src)
      Pathname.new(DIR) / filename
    end
  end
end
