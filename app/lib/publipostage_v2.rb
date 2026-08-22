# frozen_string_literal: true

class PublipostageV2 < Publipostage
  # Suffixe de `Column#id` (base64) désignant une colonne de référentiel.
  REFERENTIEL_COLUMN_ID = /\.referentiel\.data\.row\.(\w+)\z/

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
          tr.substitute("--#{k}--", [*v].join(', '))
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
      value = Array(value).join(', ')
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
      p = table.rows[0]&.cells&.[](0)&.paragraphs&.[](0)&.text_runs&.[](0) # rubocop:disable Style/SafeNavigationChainLength
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
        # 1. Construire le hash de la ligne
        row_hash = repetition.champs.each_with_object({}) do |sous_champ, hash|
          result = champ_value(sous_champ)
          expand_hash_into_result(hash, sous_champ.label, result)
        end
        # 2. Interpoler toutes les valeurs string avec le contexte complet de la ligne
        interpolate_row_values(row_hash)
      end
    when 'DropDownListChamp'
      expand_drop_down_list(champ)
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

  # Une liste déroulante adossée à un référentiel expose, à côté de la valeur
  # choisie, les colonnes de la ligne du référentiel. On les déplie comme celles
  # d'un ReferentielDePolynesieChamp, sous le nom technique de la colonne
  # (`votre_enseignant_referent_de_stage_fonction_ers`) et non sous son libellé,
  # qui est préfixé du libellé du champ et accentué.
  # Une liste ordinaire n'a pas de telle colonne : on rend alors la valeur nue,
  # pour ne pas encombrer le contexte de fusion de clés inutiles.
  def expand_drop_down_list(champ)
    columns = referentiel_columns(champ)
    return string_value_of(champ) if columns.empty?

    columns.each_with_object({ '' => champ.string_value || '' }) do |(name, value), result|
      result[".#{name}"] = expanded_column_value(convert_column_value(value))
    end
  end

  # `Column#id` est un base64 de la forme
  # « Column-type_de_champ/175731-$.referentiel.data.row.fonction_ers » pour une
  # colonne de référentiel, et « Column-type_de_champ/175727 » — sans suffixe —
  # pour la valeur d'une liste ordinaire, qui n'a rien à déplier.
  def referentiel_columns(champ)
    return [] unless champ.respond_to?(:columns) && champ.columns

    champ.columns.filter_map do |column|
      name = Base64.decode64(column.id)[REFERENTIEL_COLUMN_ID, 1]
      [name, column.string_value] if name
    end
  end

  def expand_referentiel_de_polynesie(champ)
    result = {}
    # Valeur principale (clé vide)
    result[''] = champ.string_value || ''

    # Expansion des colonnes (clés préfixées par ".")
    if champ.respond_to?(:columns) && champ.columns
      champ.columns.each do |column|
        result[".#{column.name}"] = expanded_column_value(convert_column_value(column.value))
      end
    end

    result
  end

  # Point d'extension : V3 y branche la conversion Markdown → HTML.
  def expanded_column_value(value)
    value.nil? ? '' : value
  end

  def expand_numero_dn(champ)
    result = {}
    # Valeur principale (format original, clé vide)
    result[''] = "#{champ.numero_dn}|#{champ.date_de_naissance}"

    # Expansion des sous-propriétés (clés préfixées par ".")
    result['.numero_dn'] = champ.numero_dn || ''
    result['.date_de_naissance'] = champ.date_de_naissance || ''

    result
  end

  def expand_commune_de_polynesie(champ)
    result = {}
    # Valeur principale (clé vide)
    result[''] = champ.string_value || ''

    # Expansion des propriétés de la commune (clés préfixées par ".")
    if champ.respond_to?(:commune) && champ.commune
      result['.name'] = champ.commune.name || ''
      result['.postalCode'] = champ.commune.postal_code || ''
      result['.island'] = champ.commune.island || ''
      result['.archipelago'] = champ.commune.archipelago || ''
    end

    result
  end

  # Interpoler les valeurs d'une ligne de bloc répétable avec son propre contexte
  # Remplace {champ}, {prefix;champ;suffix}, {champ?oui:non} via instanciate
  def interpolate_row_values(row_hash)
    row_hash.transform_values do |value|
      if value.is_a?(Hash)
        # Pour les champs expandus (.libelle, .parametre, etc.)
        value.transform_values { |v| interpolate_single_value(v, row_hash) }
      else
        interpolate_single_value(value, row_hash)
      end
    end
  end

  # Interpoler une valeur unique (String, Sablon::Content::HTML, ou autre)
  def interpolate_single_value(value, context)
    case value
    when String
      instanciate(value, context)
    when Struct
      # Gérer Sablon::Content::HTML : interpoler le contenu HTML
      if value.respond_to?(:html_content)
        interpolated_html = instanciate(value.html_content, context)
        Sablon.content(:html, interpolated_html)
      else
        value
      end
    else
      value
    end
  end
end
