# frozen_string_literal: true

class PublipostageV2 < Publipostage
  def version
    super + 1
  end

  def generate_docx(output_file, fields)
    doc = Docx::Document.open(@modele)
    tables = doc.tables.select { |table| fields.key?(table.xpath('w:tblPr/w:tblCaption/@w:val').text) }
    tables.each do |table|
      fill_table(table, fields)
    end
    paragraph_substitution(doc, fields)

    doc.save(output_file)
  end

  def paragraph_substitution(doc, fields)
    doc.paragraphs.each do |p|
      p.each_text_run do |tr|
        next unless tr.text.include?('--')

        fields.each do |k, v|
          tr.substitute("--#{k}--", [*v].map(&:to_s).join(','))
        end
      end
    end
  end

  def fill_table(table, fields)
    field = table.xpath('w:tblPr/w:tblCaption/@w:val').text
    last_row = table.rows.last
    if fields.key?(field) && fields[field].is_a?(Array)
      fields[field].each do |line|
        insert_row_before(last_row, line)
      end
      last_row.remove!
    else
      keys = row.keys.join(',')
      lists = row.keys.select { |_k, v| v.is_a?(Array) }.join(',')
      table.insert_text_after("La table a pour titre #{field} mais aucun champ contenant une liste porte ce nom. Clés disponibles: #{keys}, listes disponibles: #{lists}")
    end
  end

  def insert_row_before(last_row, line)
    line = line.transform_keys { |k| "--#{k}--" }.transform_values(&:to_s)
    row = last_row.copy
    row.insert_before(last_row)
    row.cells.each do |cell|
      cell.paragraphs.each do |paragraph|
        paragraph.each_text_run do |tr|
          next unless tr.text.include?('--')

          line.each do |k, v|
            tr.substitute(k, v)
          end
        end
      end
    end
  end

  private

  def champ_value(champ)
    return super unless champ.respond_to?(:__typename)

    case champ.__typename
    when 'PieceJustificativeChamp'
      excel_to_rows(champ)
    when 'RepetitionChamp'
      bloc_to_rows(champ).map { |repetition| repetition.champs.each_with_object({}) { |sous_champ, hash| hash[sous_champ.label] = champ_value(sous_champ) } }
    else
      super
    end
  end
end
