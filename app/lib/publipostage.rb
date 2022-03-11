# frozen_string_literal: true

require 'set'

class Publipostage < FieldChecker
  OUTPUT_DIR = 'tmp/publipost'
  DATA_DIR = 'storage/publipost'

  def version
    super + 26 + @calculs.map(&:version).reduce(0, &:+)
  end

  def initialize(params)
    super
    @calculs = create_tasks
    @modele = @params[:modele]
    throw 'Modèle introuvable' unless File.exist?(@modele)
    throw 'OFFICE_PATH not defined in .env file' if ENV.fetch('OFFICE_PATH').blank?
    FileUtils.mkdir_p(OUTPUT_DIR)
    FileUtils.mkdir_p(DATA_DIR)
    @states = Set.new([*(@params[:etat_du_dossier] || 'en_instruction')])
  end

  def required_fields
    super + %i[champs message modele nom_fichier]
  end

  def authorized_fields
    super + %i[calculs dossier_cible etat_du_dossier champ_source nom_fichier_lot champ_force_publipost]
  end

  def process(demarche, dossier)
    target = destination(dossier)
    return unless dossiers_have_right_state?(dossier, target)

    @dossier = dossier
    @demarche = demarche

    pdf_paths = rows.filter_map do |row|
      compute_dynamic_fields(row)
      fields = get_fields(row, params[:champs])
      generate_doc(fields) unless same_document(fields)
    end
    return unless pdf_paths.present?

    combine(pdf_paths) do |pdf_path|
      body = instanciate(@params[:message], @dossier)
      SendMessage.send_with_file(target.id, demarche.instructeur, body, pdf_path, build_filename)
      annotation_updated_on(@dossier) # to prevent infinite check
    end
  end

  private

  def combine(pdf_paths)
    Tempfile.create(['publipost', '.pdf']) do |f|
      f.binmode
      pdf = CombinePDF.new
      pdf_paths.each { |path| pdf << CombinePDF.load(path) }
      pdf.save f
      f.rewind
      yield f
    end
  end

  def excel_to_rows(champ_source)
    PieceJustificativeCache.get(champ_source.file) do |file|
      next if File.extname(file) != '.xlsx'

      xlsx = Roo::Spreadsheet.open(file)
      sheet = xlsx.sheet(0)
      header_line = header_line(sheet)
      sheet_rows(header_line, sheet)
    ensure
      xlsx&.close
    end
  end

  def sheet_rows(header_line, sheet)
    rows = []
    sheet.each_row_streaming do |row|
      rows << headers.map.with_index { |v, i| [v, row[i].value] }.to_h if row[1].coordinate[0] > header_line && row[1].value.present?
    end
    rows
  end

  def header_line(sheet)
    header_line = 0
    max = 0
    sheet.each_row_streaming do |row|
      cell = row.find { |c| c.value.nil? }
      if (count = cell.coordinate[1]) > max
        max = count
        header_line = cell.coordinate[0]
      end
    end
    header_line
  end

  def bloc_to_rows(champ_source)
    champs = champ_source.champs
    rows = []
    bloc = FieldList.new
    champs.each do |champ|
      if bloc[champ.label].present?
        rows << bloc
        bloc = FieldList.new
      end
      bloc << champ
    end
    rows << bloc
  end

  def rows
    champ_source_name = @params[:champ_source]
    return [@dossier] if champ_source_name.blank?

    champs_source = field_values(@dossier, champ_source_name)
    champs_source.map do |champ_source|
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

  def dossiers_have_right_state?(dossier, target)
    return false unless @states.include?(dossier.state)

    (target == dossier || @states.include?(target.state))
  end

  def destination(dossier)
    field_name = @params[:dossier_cible]
    return dossier if field_name.blank?

    field = field_values(dossier, field_name)&.first
    Rails.logger.log('Le champ field_name est vide') if field.blank?
    field&.dossier || dossier
  end

  def same_document(fields)
    datafile = "#{DATA_DIR}/#{instanciate(@params[:nom_fichier], fields)}.yml"
    fields['#checksum'] = FileUpload.checksum(@modele)
    same = File.exist?(datafile) && YAML.load_file(datafile) == fields
    File.write(datafile, YAML.dump(fields)) unless same
    same
  end

  def build_filename
    definition = @params[:nom_fichier_lot] || @params[:nom_fichier]
    return 'document.pdf' if definition.blank?

    instanciate(definition, @dossier)
  end

  def instanciate(template, source)
    template.gsub(/{[^{}]+}/) do |matched|
      variable = matched[1..-2]
      get_values_of(source, variable, variable, '')&.first
    end
  end

  def generate_doc(row)
    basename = "#{OUTPUT_DIR}/#{instanciate(@params[:nom_fichier], row)}"
    docx = "#{basename}.docx"

    context = row.transform_keys { |k| k.gsub(/\s/, '_').gsub(/[()]/, '') }
    template = Sablon.template(File.expand_path(@modele))
    template.render_to_file docx, context
    stdout_str, stderr_str, status = Open3.capture3(ENV['OFFICE_PATH'], '--headless', '--convert-to', 'pdf', '--outdir', OUTPUT_DIR, docx)
    throw "Unable to convert #{docx} to pdf\n#{stdout_str}#{stderr_str}" if status != 0
    "#{basename}.pdf"
  end

  MD_FIELDS =
    {
      'ID' => 'number',
      'Email' => 'usager.email',
      'Archivé' => 'archived',
      'Civilité' => 'demandeur.civilite',
      'Nom' => 'demandeur.nom',
      'Prénom' => 'demandeur.prenom',
      'État du dossier' => 'state',
      'Dernière mise à jour le' => 'date_derniere_modification',
      'Déposé le' => 'date_passage_en_construction',
      'Passé en instruction le' => 'date_passage_en_instruction',
      'Traité le' => 'date_traitement',
      'Motivation de la décision' => 'motivation',
      'Instructeurs' => 'groupe_instructeur.instructeurs.email',
      'Établissement Numéro TAHITI' => 'demandeur.siret',
      'Établissement siège social' => '', # not implemented in Mes-Démarches
      'Établissement NAF' => 'demandeur.naf',
      'Établissement libellé NAF' => 'demandeur.libelle_naf',
      'Établissement Adresse' => 'demandeur.adresse',
      'Établissement numero voie' => 'demandeur.numero_voie',
      'Établissement type voie' => 'demandeur.type_voie',
      'Établissement nom voie' => 'demandeur.nom_voie',
      'Établissement complément adresse' => 'demandeur.complement_adresse',
      'Établissement code postal' => 'demandeur.code_postal',
      'Établissement localité' => 'demandeur.localite',
      'Établissement code INSEE localité' => '', # not implemented in Mes-Démarches
      'Entreprise SIREN' => 'demandeur.entreprise.siren',
      'Entreprise capital social' => 'demandeur.entreprise.capital_social',
      'Entreprise numero TVA intracommunautaire' => 'demandeur.entreprise.numero_tva_intracommunautaire',
      'Entreprise forme juridique' => 'demandeur.entreprise.forme_juridique',
      'Entreprise forme juridique code' => 'demandeur.entreprise.forme_juridique_code',
      'Entreprise nom commercial' => 'demandeur.entreprise.nom_commercial',
      'Entreprise raison sociale' => 'demandeur.entreprise.raison_sociale',
      'Entreprise Numéro TAHITI siège social' => 'demandeur.entreprise.siret_siege_social',
      'Entreprise code effectif entreprise' => 'demandeur.entreprise.code_effectif_entreprise',
      'Entreprise date de création' => 'demandeur.entreprise.date_creation',
      'Entreprise nom' => 'demandeur.entreprise.nom',
      'Entreprise prénom' => 'demandeur.entreprise.prenom',
      'Association RNA' => 'demandeur.association.rna',
      'Association titre' => 'demandeur.association.titre',
      'Association objet' => 'demandeur.association.objet',
      'Association date de création' => 'demandeur.association.date_creation',
      'Association date de déclaration' => 'demandeur.association.date_declaration',
      'Association date de publication' => 'demandeur.association.date_declaration'
    }.freeze

  def get_fields(row, definitions)
    result = { 'Dossier' => @dossier.number }
    definitions.each do |definition|
      column, field, par_defaut = load_definition(definition)
      result[column] = [*get_values_of(row, column, field, par_defaut)].join(',')
    end
    result
  end

  # FieldList acts as a dossier allowing looking for champs
  class FieldList
    def initialize
      @champs = {}
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

  def get_values_of(row, column, field, par_defaut = nil)
    return par_defaut unless field

    # from computed values
    value = @computed[column] if @computed.is_a? Hash
    return [*value] if value.present?

    # from excel soource
    value = row[column] if row.is_a? Hash
    return [*value] if value.present?

    # from repetitive champs
    champs = field_values(row, field, log_empty: false) if row.is_a? FieldList
    return champs_to_values(champs) if champs.present?

    # from dossier champs
    champs = field_values(@dossier, field, log_empty: false)
    champs_to_values(champs) || [par_defaut]
  end

  def load_definition(param)
    if param.is_a?(Hash)
      par_defaut = param['par_defaut'] || ''
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
    field[(field.rindex('.') || -1) + 1..]
  end

  def champs_to_values(champs)
    champs.map(&method(:champ_value)).compact.select(&:present?)
  end

  def dossier_values(dossier, field)
    path = MD_FIELDS[field]
    return [] if path.nil?

    path.split(/\./).reduce(dossier) do |o, f|
      case o
      when GraphQL::Client::List, Array
        o.map { |elt| elt.send(f) }
      else
        [o.send(f)] if o.present?
      end
    end
  end

  def champ_value(champ)
    return nil unless champ

    return champ.strftime('%d/%m/%Y') if champ.is_a?(Date)

    return champ unless champ.respond_to?(:__typename) # direct value

    case champ.__typename
    when 'TextChamp', 'IntegerNumberChamp', 'DecimalNumberChamp', 'CiviliteChamp'
      champ.value || ''
    when 'MultipleDropDownListChamp'
      champ.values
    when 'LinkedDropDownListChamp'
      "#{champ.primary_value}/#{champ.secondary_value}"
    when 'DateTimeChamp'
      date_value(champ, '%d/%m/%Y %H:%M')
    when 'DateChamp'
      date_value(champ, '%d/%m/%Y')
    when 'CheckboxChamp'
      champ.value
    when 'NumeroDnChamp'
      "#{champ.numero_dn}|#{champ.date_de_naissance}"
    when 'DossierLinkChamp', 'SiretChamp'
      champ.string_value
    when 'PieceJustificativeChamp'
      champ&.file&.filename
    else
      puts champ.__typename
    end
  end

  def date_value(value, format)
    if value.present?
      Date.iso8601(champ.value).strftime(format)
    else
      ''
    end
  end

  def compute_dynamic_fields(row)
    @computed = compute_cells(row) if @calculs.present?
  end

  def compute_cells(row)
    @calculs.map { |task| task.process_row(@demarche, @dossier, row) }.reduce(&:merge)
  end

  def create_tasks
    taches = params[:calculs]
    return [] if taches.nil?

    taches.flatten.map.with_index do |description, position|
      if description.is_a?(String)
        Object.const_get(description.camelize).new({}).tap_name("#{position}:#{description}")
      else
        # hash
        description.map { |taskname, params| Object.const_get(taskname.camelize).new(params).tap_name("#{position}:#{taskname}") }
      end
    end.flatten
  end

  def field_values(dossier, field, log_empty: true)
    return nil if dossier.nil? || field.blank?

    object_field_values(dossier, field, log_empty)
  end

  def object_field_values(source, field, log_empty)
    objects = [source]
    field.split(/\./).each do |name|
      objects = objects.flat_map do |object|
        object = object.dossier if object.respond_to?(:dossier)
        r = []
        r += select_champ(object.champs, name) if object.respond_to?(:champs)
        if object.respond_to?(:annotations)
          r += select_champ(object.annotations, name)
          r += dossier_values(object, name) if r.empty?
        end
        r += attributes(object, name) if r.empty? && object.respond_to?(name)
        r
      end
      Rails.logger.warn("Sur le dossier #{@dossier.number}, le champ #{field} est vide.") if log_empty && objects.blank?
    end
    objects
  end

  def attributes(object, name)
    values = Array(object.send(name))
    return values unless name.match?(/date/i)

    values.map { |v| v.is_a?(String) ? Date.iso8601(v) : v }
  end

  def select_champ(champs, name)
    champs.select { |champ| champ.label == name }
  end
end
