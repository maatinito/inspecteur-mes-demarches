# frozen_string_literal: true

class PublipostageV2 < Publipostage
  def version
    super + 1
  end

  def generate_docx(output_file, fields)
    doc = Docx::Document.open(VerificationService.file_manager.filepath(@template).to_s)
    doc.tables.each do |table|
      process_table(table, fields)
    end
    paragraph_substitution(doc, fields)
    paragraph_substitution_v2(doc, fields)

    doc.save(output_file)
  end

  def paragraph_substitution(doc, fields)
    doc.paragraphs.each do |p|
      p.each_text_run do |tr|
        next unless tr.text.include?('--')

        [*fields].each do |k, v|
          # ActiveSupport::NumberHelper.number_to_currency(123456789, unit: '', delimiter: ' ', precision: 0)
          tr.substitute("--#{k}--", [*v].map(&:to_s).join(', '))
        end
        insert_line_breaks(tr)
      end
    end
  end

  def paragraph_substitution_v2(doc, fields)
    doc.paragraphs.each do |p|
      substitution_in_text_run(fields, p)
      substitution_in_field_simple(fields, p)
    end
  end

  def substitution_in_text_run(fields, paragraph)
    variable, value = nil
    paragraph.each_text_run do |tr|
      nodeset = tr.xpath("w:instrText[starts-with(., ' MERGEFIELD')]")
      if nodeset.size.positive? && (text = nodeset.text)
        variable, value = definition(fields, text)
        next
      end
      next unless variable.present? && tr.text.match(/«#{variable}»/i)

      tr.substitute(/«#{variable}»/i, value)
      insert_line_breaks(tr.node)
      variable = nil
    end
  end

  def substitution_in_field_simple(fields, paragraph)
    paragraph.xpath('w:fldSimple').each do |node|
      variable, value = definition(fields, node.attribute('instr').text)
      w_r = node.at_xpath('w:r')
      w_t = w_r.at_xpath('w:t')
      w_t.content = w_t.content.gsub(/«#{variable}»/i, value)
      insert_line_breaks(w_r)
    end
  end

  def definition(fields, text)
    match = text.match(/MERGEFIELD\s+(?:"([^"]+)"|([^" ]+))/)
    variable = match[1].presence || match[2] if match
    if variable
      options = text.scan(/\\(. (?:\w+|"[^"]+"))/).flatten.to_set
      value = fields.fetch(variable) { Rails.env.development? || Rails.env.test? ? "[#{variable} inconnue]" : '' }
      value = Array(value).map(&:to_s).join(', ')
      value = normalize_value(value, options)
      variable = Regexp.escape(variable)
      [variable, value]
    else
      []
    end
  end

  def normalize_value(input, options)
    options.reduce(input) do |value, option|
      case option
      when '* Lower'
        value.downcase
      when '* Upper'
        value.upcase
      when '* FirstCap'
        value.capitalize
      when '* Caps'
        value.split.map(&:capitalize).join(' ')
      else
        value
      end
    end
  end

  def insert_line_breaks(r_node)
    xt = r_node.at_xpath('w:t')
    segments = xt.content.split(/\r*\n\r*/)
    return unless segments.present? && segments.size > 1

    xt.content = segments.first
    template = r_node.dup
    template.prepend_child(Nokogiri::XML::Node.new('w:br', r_node.document))
    segments[1..].each do |segment|
      new_r = template.dup
      new_r.at_xpath('w:t').content = segment
      r_node = r_node.add_next_sibling(new_r)
    end
  end

  def process_table(table, fields)
    field = table.xpath('w:tblPr/w:tblCaption/@w:val').text
    fill_table(table, fields, field) if field.present?
    table_substitution(table, fields)
  end

  def fill_table(table, fields, field)
    last_row = table.rows.last
    if fields.key?(field) && fields[field].is_a?(Array)
      fields[field].each do |sub_fields|
        insert_row_before(last_row, sub_fields.presence || {})
      end
      last_row.remove!
    elsif Rails.env.development? || Rails.env.test?
      keys = fields.keys.join(', ')
      p = table.rows[0]&.cells&.[](0)&.paragraphs&.[](0)&.text_runs&.[](0)
      p&.text = "La table a pour titre #{field} mais aucun champ contenant une liste porte ce nom. Clés disponibles: #{keys}"
    end
  end

  def table_substitution(table, fields)
    table.rows.each do |row|
      row.cells.each do |cell|
        paragraph_substitution(cell, fields)
        paragraph_substitution_v2(cell, fields)
      end
    end
  end

  def insert_row_before(last_row, sub_fields)
    row = last_row.copy
    row.insert_before(last_row)
    row.cells.each do |cell|
      paragraph_substitution(cell, sub_fields)
      paragraph_substitution_v2(cell, sub_fields)
    end
  end

  private

  def champ_value(champ)
    return super unless champ.respond_to?(:__typename)

    case champ.__typename
    when 'PieceJustificativeChamp'
      excel_to_rows(champ)
    when 'RepetitionChamp'
      bloc_to_rows(champ).map do |repetition|
        repetition.champs.each_with_object({}) do |sous_champ, hash|
          result = champ_value(sous_champ)
          if result.is_a?(Hash)
            # Si champ_value retourne une Hash (champ expansé), on fusionne
            hash.merge!(result)
          else
            # Sinon, on garde le comportement classique
            hash[sous_champ.label] = result
          end
        end
      end
    when 'ReferentielDePolynesieChamp'
      expand_referentiel_de_polynesie(champ)
    when 'NumeroDnChamp'
      expand_numero_dn(champ)
    when 'CommuneDePolynesieChamp', 'CodePostalDePolynesieChamp'
      expand_commune_de_polynesie(champ)
    else
      super
    end
  end

  def expand_referentiel_de_polynesie(champ)
    result = {}
    # Valeur principale
    result[champ.label] = champ.string_value || ''

    # Expansion des colonnes
    if champ.respond_to?(:columns) && champ.columns
      champ.columns.each do |column|
        key = "#{champ.label}.#{column.name}"
        value = convert_column_value(column.value)
        result[key] = value.nil? ? '' : value
      end
    end

    result
  end

  def expand_numero_dn(champ)
    result = {}
    # Valeur principale (format original)
    result[champ.label] = "#{champ.numero_dn}|#{champ.date_de_naissance}"

    # Expansion des sous-propriétés
    result["#{champ.label}.numero_dn"] = champ.numero_dn || ''
    result["#{champ.label}.date_de_naissance"] = champ.date_de_naissance || ''

    result
  end

  def expand_commune_de_polynesie(champ)
    result = {}
    # Valeur principale
    result[champ.label] = champ.string_value || ''

    # Expansion des propriétés de la commune
    if champ.respond_to?(:commune) && champ.commune
      result["#{champ.label}.name"] = champ.commune.name || ''
      result["#{champ.label}.postalCode"] = champ.commune.postal_code || ''
      result["#{champ.label}.island"] = champ.commune.island || ''
      result["#{champ.label}.archipelago"] = champ.commune.archipelago || ''
    end

    result
  end
end
