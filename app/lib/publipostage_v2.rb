# frozen_string_literal: true

class PublipostageV2 < Publipostage
  def version
    super + 1
  end

  def generate_docx(output_file, fields)
    doc = Docx::Document.open(@modele)
    doc.tables.each do |table|
      process_table(table, fields)
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

  def process_table(table, fields)
    field = table.xpath('w:tblPr/w:tblCaption/@w:val').text
    if field.present?
      fill_table(table, fields, field)
    end
    table_substitution(table, fields)
  end

  def fill_table(table, fields, field)
    last_row = table.rows.last
    if fields.key?(field) && fields[field].is_a?(Array)
      fields[field].each do |sub_fields|
        insert_row_before(last_row, sub_fields)
      end
      last_row.remove!
    else
      keys = fields.keys.join(',')
      p = table.rows[0]&.cells[0]&.paragraphs[0]&.text_runs[0]
      p&.text = "La table a pour titre #{field} mais aucun champ contenant une liste porte ce nom. Clés disponibles: #{keys}"
    end
  end

  def table_substitution(table, fields)
    table.rows.each do |row|
      row.cells.each do |cell|
        paragraph_substitution(cell, fields)
      end
    end
  end

  def insert_row_before(last_row, sub_fields)
    row = last_row.copy
    row.insert_before(last_row)
    row.cells.each do |cell|
      paragraph_substitution(cell, sub_fields)
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
