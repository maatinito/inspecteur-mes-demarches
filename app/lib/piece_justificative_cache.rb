class PieceJustificativeCache
  DIR = 'storage/pjs'
  SIZE = 50 * 1024 * 1024

  class << self
    def get(md_file)
      pathname = pathname(md_file.filename, md_file.checksum)
      unless pathname.exist?
        File.open(pathname, 'wb') do |f|
          IO.copy_stream(URI.parse(md_file.url).open, f)
          f.close
        end
        maintenance
      end
      yield pathname.to_s
    end

    def put(src)
      dst = pathname(src, FileUpload.checksum(src))
      puts "#{src} ==> #{dst}"
      FileUtils.cp(src, dst)
      maintenance
    end

    def maintenance
      files = Dir.glob(DIR + '/*').select { |f| File.file?(f) }.sort_by { |f| File.mtime(f) }
      size = files.map { |f| File.size(f) }.reduce(&:+)
      while size > SIZE && files.size > 2 # always keep at least last file
        file = files.first
        size -= File.size(file)
        File.delete(file)
        files.shift
      end
    end

    private

    def pathname(src, checksum)
      checksum = checksum.gsub(/[\/\\]/, '_')
      filename = checksum + File.extname(src)
      dst = Pathname.new(DIR) / filename
    end
  end
end
