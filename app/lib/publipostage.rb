# frozen_string_literal: true

require 'set'

class Publipostage < FieldChecker
  DIR = "tmp/publipost"

  def initialize(params)
    super
    @calculs = create_tasks
    @modele = @params[:modele]
    throw "Modèle introuvable" unless File.exists?(@modele)
    throw "OFFICE_PATH not defined in .env file" if ENV.fetch("OFFICE_PATH").blank?
    FileUtils.mkdir_p(DIR)
  end

  def required_fields
    super + %i[champs message modele]
  end

  def authorized_fields
    super + %i[calculs]
  end

  def process(_demarche, dossier)
    @dossier = dossier
    compute_dynamic_fields
    fields = get_fields(params[:champs])
    doc_path = generate_doc(fields)
    # SetAnnotationValue.set_piece_justificative(dossier, instructeur_id, annotation, doc_path, 'convention.pdf')

  end

  def check(dossier)
    process(nil, dossier)
  end

  def version
    super + 5
  end

  private

  def generate_doc(line)
    context = line.to_h { |k, v| [k.gsub(/\s/, '_'), v] }
    template = Sablon.template(File.expand_path(@modele))
    docx = "#{DIR}/#{dossier.number}.docx"
    template.render_to_file docx, context
    stdout_str, stderr_str, status = Open3.capture3(*[ENV['OFFICE_PATH'], '--headless', '--convert-to', 'pdf', '--outdir', DIR, docx])
    throw "Unable to convert #{docx} to pdf\n#{stdout_str}#{stderr_str}" if status != 0
    "#{DIR}/#{dossier.number}.pdf"
  end

  def normalize_line_for_csv(line)
    line.map do |cells|
      cells = Array(cells)
      cells.map! { |v| v.is_a?(Date) ? v.strftime('%d/%m/%Y') : v }
      cells.join('|').strip.tr(';', '/')
    end
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

  def get_fields(fields)
    fields.reduce({ 'Dossier' => @dossier.number }, &method(:set_field))
  end

  def set_field(hash, param)
    name, field, par_defaut = definition(param)
    hash[name] = get_value_of(field, par_defaut)&.first
    hash
  end

  def get_value_of(field, par_defaut)
    return par_defaut unless field

    value = @computed[field] if @computed.is_a? Hash
    return value if value.present?

    champs = field_values(@dossier, field, log_empty: false)
    return champs_to_values(champs) || []

    # add_message(Message::WARN, "Impossible de trouver le champ #{field}")
    par_defaut
  end

  def definition(param)
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
    field[(field.rindex('.') || -1) + 1..-1]
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

  def date_value(champ, format)
    if champ.value.present?
      Date.iso8601(champ.value).strftime(format)
    else
      add_message(Message::WARN, "champ #{champ.label} vide")
      ''
    end
  end

  def compute_dynamic_fields
    @computed = compute_cells if @calculs.present?
  end

  def compute_cells
    @calculs.map { |task| task.process_dossier(@dossier) }.reduce(&:merge)
  end

  def create_tasks
    taches = params[:calculs]
    return [] if taches.nil?

    taches.flatten.map do |task|
      case task
      when String
        Object.const_get(task.camelize).new(job, {})
      when Hash
        task.map { |name, params| Object.const_get(name.camelize).new(@job, params || {}) }
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
          r += dossier_values(object, name)
        end
        r += attributes(object, name) if object.respond_to?(name)
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

  def annotation_values(name, log_empty: true)
    return nil if @dossier.nil? || name.blank?

    objects = @dossier.annotations.select { |champ| champ.label == name }
    Rails.logger.warn("Sur le dossier #{@dossier.number}, l'annotation #{name} est vide.") if log_empty && objects.blank?
    objects
  end

  def field_value(field_name)
    field_values(field_name)&.first
  end

end
