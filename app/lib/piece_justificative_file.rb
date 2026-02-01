# frozen_string_literal: true

# Wrapper pour les fichiers PieceJustificative utilisé par Sablon dans PublipostageV3.
# Permet un accès lazy aux images, liens, et données Excel/CSV.
#
# Exemples d'utilisation dans les templates Sablon :
#
# Images :
#   «photos:each(photo)»
#     «@photo.image:start»[placeholder image]«@photo.image:end»
#     Nom: «=photo.nom» (Taille: «=photo.taille»)
#   «photos:endEach»
#
# Excel/CSV :
#   «fichiers:each(fichier)»
#     «fichier.rows:each(ligne)»
#       «=ligne.Colonne1» - «=ligne.Colonne2»
#     «fichier.rows:endEach»
#   «fichiers:endEach»
#
# Liens (sans télécharger) :
#   «documents:each(doc)»
#     «=doc.nom» («=doc.taille») - «=doc.lien»
#   «documents:endEach»
#
# Conditionnel (seulement les images) :
#   «pieces:each(piece)»
#     «piece.image:if(present?)»
#       «@piece.image:start»[placeholder]«@piece.image:end»
#     «piece.image:endIf»
#   «pieces:endEach»
#
class PieceJustificativeFile
  attr_reader :filename
  alias nom filename

  def initialize(file)
    @file = file
    @filename = file.filename
  end

  # IMAGES : Lazy loading de l'image pour insertion dans le document
  # Retourne un objet Sablon.content(:image) ou nil si ce n'est pas une image
  def image
    return @image if defined?(@image)
    return @image = nil unless image_file?

    downloaded = PieceJustificativeCache.get(@file)
    @image = Sablon.content(:image, downloaded)
  end

  # LIENS : URL du fichier (éphémère pour l'instant via API mes-démarches)
  def link
    @file.url
  end
  alias lien link

  # EXCEL/CSV : Lazy loading des lignes du tableau
  # Retourne un Array de Hash { "Colonne" => "valeur" }
  def rows
    return @rows if defined?(@rows)
    return @rows = [] unless tabular_file?

    @rows = parse_tabular_file
  end
  alias lignes rows

  # MÉTADONNÉES : Taille formatée du fichier (ex: "1.5 MB")
  def size
    byte_size = @file.byte_size || 0
    ActiveSupport::NumberHelper.number_to_human_size(byte_size)
  end
  alias taille size

  # MÉTADONNÉES : Type/extension du fichier sans le point (ex: "jpg", "xlsx", "pdf")
  def type
    extension.gsub('.', '')
  end

  # PRÉDICATS : Est-ce une image ?
  def image?
    image_file?
  end

  # PRÉDICATS : Est-ce un fichier Excel/CSV ?
  def excel?
    tabular_file?
  end

  private

  def image_file?
    %w[.jpg .jpeg .png .gif .bmp .webp].include?(extension)
  end

  def tabular_file?
    %w[.xlsx .csv].include?(extension)
  end

  def extension
    File.extname(@filename).downcase
  end

  def parse_tabular_file
    PieceJustificativeCache.get(@file) do |file|
      case extension
      when '.xlsx'
        parse_xlsx(file)
      when '.csv'
        parse_csv(file)
      end
    end
  end

  def parse_xlsx(file)
    xlsx = Roo::Spreadsheet.open(file)
    sheet = xlsx.sheet(0)
    header_line = find_header_line(sheet)
    extract_sheet_rows(header_line, sheet)
  ensure
    xlsx&.close
  end

  def parse_csv(file)
    Roo::CSV.new(file).parse(headers: true)[1..].map do |row|
      row.transform_values do |v|
        if v.match(/^\d+$/)
          v.to_i
        else
          v.match(/^[\d.]+$/) ? v.to_f : v
        end
      end
    end
  end

  # Trouve la ligne d'en-tête dans une feuille Excel
  # (la ligne avec le plus grand nombre de cellules remplies)
  def find_header_line(sheet)
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

  # Extrait les lignes d'une feuille Excel en utilisant la ligne d'en-tête
  def extract_sheet_rows(header_line, sheet)
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
end
