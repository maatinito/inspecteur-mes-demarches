# frozen_string_literal: true

class FieldChecker < InspectorTask
  attr_accessor :dossier
  attr_reader :messages, :accessed_fields, :updated_dossiers, :dossiers_to_recheck

  attr_writer :demarche

  def initialize(params)
    super
    @messages = []
    @updated_dossiers = Set.new
    @dossiers_to_recheck = Set.new
    etat_du_dossier = @params[:etat_du_dossier] || ['en_construction']
    etat_du_dossier = etat_du_dossier.split(/\s*,\s*/) if etat_du_dossier.is_a?(String)
    @states = Set.new(etat_du_dossier)
  end

  def process(demarche, dossier)
    @messages = []
    @updated_dossiers = Set.new
    @dossiers_to_recheck = Set.new
    @dossier = dossier
    @demarche = demarche
    # MicrosoftGraphCore::Authentication::OAuthAuthenticationProvider.new(context, nil, ['https://graph.microsoft.com/.default'])
    #
    # context = MicrosoftKiotaAuthenticationOAuth::ClientCredentialContext.new(tenant_id, user, password)
    # authentication_provider = MicrosoftGraphCore::Authentication::OAuthAuthenticationProvider.new(context, nil, ['https://graph.microsoft.com/.default'])
    # adapter = MicrosoftGraph::GraphRequestAdapter.new(authentication_provider)
    # client = MicrosoftGraph::GraphServiceClient.new(adapter)
    # client.sites.get.resume
  end

  def control(dossier)
    @messages = []
    @updated_dossiers = Set.new
    @dossiers_to_recheck = Set.new
    @dossier = dossier
    @demarche = demarche
    check(dossier)
  end

  def authorized_fields
    super + %i[etat_du_dossier]
  end

  def must_check?(md_dossier)
    @states.include?(md_dossier.state)
  end

  def check(_dossier)
    raise "check(dossier) should be implemented by class #{self}"
  end

  def fields(name, warn_if_empty: true)
    dossier_fields(@dossier, name, warn_if_empty:)
  end

  def field(name, warn_if_empty: true)
    fields(name, warn_if_empty:)&.first
  end

  def annotations(name, warn_if_empty: true)
    dossier_annotations(@dossier, name, warn_if_empty:)
  end

  def annotation(name, warn_if_empty: true)
    annotations(name, warn_if_empty:)&.first
  end

  def param_fields(param_name, warn_if_empty: true)
    fields(@params[param_name], warn_if_empty:)
  end

  def param_field(param_name, warn_if_empty: true)
    param_fields(param_name, warn_if_empty:)&.first
  end

  def param_annotations(param_name, warn_if_empty: true)
    annotations(@params[param_name], warn_if_empty:)
  end

  def param_annotation(param_name, warn_if_empty: true)
    param_annotations(param_name, warn_if_empty:)&.first
  end

  def dossier_field(dossier, name, warn_if_empty: true)
    dossier_fields(dossier, name, warn_if_empty:)&.first
  end

  def dossier_fields(dossier, path, warn_if_empty: true)
    return nil if dossier.nil? || path.blank?

    objects = [*dossier]
    path.split('.').each do |name|
      objects = objects.flat_map { |object| object.champs.select { |champ| champ.label == name } }
      Rails.logger.warn("Sur le dossier #{dossier.number}, le champ #{name} est vide.") if warn_if_empty && objects.blank?
    end
    objects
  end

  def dossier_annotations(dossier, path, warn_if_empty: true)
    return nil if dossier.nil? || path.blank?

    names = path.split('.')
    objects = [*dossier]
    method = :annotations
    names.each do |name|
      objects = objects.flat_map { |object| object.send(method).select { |champ| champ.label == name } }
      Rails.logger.warn("Sur le dossier #{dossier.number}, l'annotation #{name} est vide.") if warn_if_empty && objects.blank?
      method = :champs
    end
    objects
  end

  def select_champ(champs, name)
    champs.select { |champ| champ.label == name }
  end

  def attributes(object, name)
    values = Array(object.send(name))
    return values unless name.match?(/date/i)

    values.map do |v|
      if v.is_a?(String)
        v.include?('T') ? DateTime.iso8601(v) : Date.iso8601(v)
      else
        v
      end
    end
  end

  def object_field_values(source, field, log_empty: true)
    return [] if source.blank? || field.blank?

    objects = [*source]
    field.split('.').each do |name|
      objects = objects.flat_map do |object|
        object = object.dossier if object.respond_to?(:dossier)
        r = []
        r += select_champ(object.champs, name) if object.respond_to?(:champs)
        r += select_champ(object.annotations, name) if object.respond_to?(:annotations)
        r += attributes(object, name) if object.respond_to?(name)
        r += select_referentiel_column(object, name) if referentiel_de_polynesie?(object)
        r
      end
      Rails.logger.warn("Sur le dossier #{@dossier.number}, le champ #{field} est vide.") if log_empty && objects.blank?
    end
    objects
  end

  def champs_to_values(champs)
    champs.flat_map(&method(:champ_value)).compact.select(&:present?)
  end

  def champ_value(champ)
    return nil unless champ
    return champ.strftime('%d/%m/%Y à %Hh%M') if champ.is_a?(DateTime)
    return champ.strftime('%d/%m/%Y') if champ.is_a?(Date)
    return champ.to_s if champ.is_a? GraphQL::Client::Schema::EnumType::EnumValue
    return champ unless champ.respond_to?(:__typename) # direct value

    graphql_champ_value(champ)
  end

  def graphql_champ_value(champ) # rubocop:disable Metrics/MethodLength
    case champ.__typename
    when 'TextChamp', 'IntegerNumberChamp', 'DecimalNumberChamp'
      champ.value || ''
    when 'CheckboxChamp', 'YesNoChamp'
      champ.value ? 'Oui' : 'Non'
    when 'CiviliteChamp'
      expand_civilite(champ.value.to_s)
    when 'MultipleDropDownListChamp'
      champ.values
    when 'LinkedDropDownListChamp'
      "#{champ.primary_value}/#{champ.secondary_value}"
    when 'DatetimeChamp', 'DateChamp'
      date_value(champ, '%d/%m/%Y')
    when 'NumeroDnChamp'
      "#{champ.numero_dn}|#{champ.date_de_naissance}"
    when 'DossierLinkChamp', 'SiretChamp', 'VisaChamp', 'ReferentielDePolynesieChamp', 'CommuneDePolynesieChamp', 'CodePostalDePolynesieChamp'
      string_value_of(champ)
    when 'PieceJustificativeChamp'
      champ.files.map(&:filename).join(',')
    when 'TitreIdentiteChamp'
      "Titre d'identité"
    when 'TeFenuaChamp'
      'TeFenuaChamp'
    else
      raise "Unknown field type #{champ.label}:#{champ.__typename}"
    end
  end

  def date_value(champ, format)
    if champ.present? && champ.value.present?
      Date.iso8601(champ.value).strftime(format)
    else
      ''
    end
  end

  def referentiel_de_polynesie?(object)
    object.respond_to?(:__typename) && object.__typename == 'ReferentielDePolynesieChamp'
  end

  def select_referentiel_column(champ, column_name)
    return [] unless champ.respond_to?(:columns)

    column = champ.columns.find { |c| c.name == column_name }
    return [] unless column

    [convert_column_value(column.value)]
  end

  def convert_column_value(value)
    return nil if value.nil? || value == ''

    # Try to parse as boolean
    return true if %w[true vrai].include?(value.downcase)
    return false if %w[false faux].include?(value.downcase)

    # Try to parse as date
    if value.match?(%r{^\d{1,4}[-/.]\d{1,2}[-/.]\d{1,4}$})
      begin
        # Force French format for dates with slashes (dd/mm/yyyy)
        return Date.strptime(value, '%d/%m/%Y') if value.match?(%r{^\d{1,2}/\d{1,2}/\d{4}$})

        return Date.parse(value)
      rescue Date::Error
        # Not a valid date, continue
      end
    end

    # Try to parse as number
    if value.match?(/^-?\d+$/)
      return value.to_i
    elsif value.match?(/^-?\d+\.\d+$/)
      return value.to_f
    end

    # Return as string by default
    value
  end

  def add_message(champ, valeur, message)
    @messages << Message.new(field: champ, value: valeur, message:)
  end

  def dossier_updated(dossier)
    @updated_dossiers << dossier.number
  end

  def dossier_updated?(dossier)
    @updated_dossiers.include?(dossier.number)
  end

  def recheck(dossier)
    @dossiers_to_recheck << dossier if dossier.present?
  end

  def instructeur_id_for(demarche, dossier)
    first_instructeur(dossier) || demarche.instructeur
  end

  def instructeur_id
    instructeur_id_for(@demarche, @dossier)
  end

  def first_instructeur(dossier)
    d = MesDemarches.query(MesDemarches::Queries::Instructeurs, variables: { number: dossier.number })
    raise StandardError, d.errors.messages.values.join(', ') if d.errors.present?

    d.data.dossier.instructeurs.first&.id
  end

  def instanciate(template, source = nil)
    # Traiter les expressions ternaires en premier
    template = process_ternary_expressions(template, source)

    # Ensuite traiter les expressions normales
    template.gsub(/{(?:([^{};]*);)?([^{}]+?)(?:;([^{};]*))?}/) do |_matched|
      m = ::Regexp.last_match # 3 matches : prefix, variable name to look for and postfix
      value = get_values_of(source, m[2], '').join(', ')
      value.present? ? "#{m[1]}#{value}#{m[3]}" : ''
    end
  end

  def process_ternary_expressions(template, source)
    # Syntaxes supportées: {field?yes:no}, {field ? yes : no}, {field ? "yes text" : "no text"}
    template.gsub(/{([^{}]+\?[^{}]+:[^{}]+)}/) do |_matched|
      expression = ::Regexp.last_match(1)
      parse_and_evaluate_ternary(expression, source)
    end
  end

  private

  def expand_civilite(value)
    case value
    when 'M.', 'M'
      'Monsieur'
    when 'Mme', 'Mlle'
      'Madame'
    else
      value
    end
  end

  def string_value_of(champ)
    champ.string_value
  rescue StandardError => e
    Rails.logger.error "Error on #{champ.to_h} : #{champ.class} => (#{champ.class.ancestors.first(5)}): #{e.message}"
    raise e
  end

  def parse_and_evaluate_ternary(expression, source)
    question_pos = expression.index('?')
    colon_pos = expression.rindex(':')

    return "{#{expression}}" unless question_pos && colon_pos && question_pos < colon_pos

    condition_field = expression[0...question_pos].strip
    true_value = expression[(question_pos + 1)...colon_pos].strip.gsub(/^["']|["']$/, '')
    false_value = expression[(colon_pos + 1)..].strip.gsub(/^["']|["']$/, '')

    value = get_values_of(source, condition_field, nil).first
    evaluate_ternary_condition(value, true_value, false_value)
  end

  def evaluate_ternary_condition(value, true_value, false_value)
    case value
    when TrueClass then true_value
    when FalseClass, nil then false_value
    when String then evaluate_string_condition(value, true_value, false_value)
    when Numeric then value.zero? ? false_value : true_value
    else value.present? ? true_value : false_value
    end
  end

  def evaluate_string_condition(value, true_value, false_value)
    if %w[true oui yes vrai t o y v 1].include?(value.downcase)
      true_value
    elsif %w[false non no faux f n 0].include?(value.downcase)
      false_value
    else
      value.present? ? true_value : false_value
    end
  end

  def get_values_of(source, field, par_defaut = nil)
    return par_defaut unless field

    # if source is a Hash
    value = humanize(source[field.to_sym] || source[field]) if source.is_a? Hash
    return [*value] if value.present?

    # if source has champs
    champs = object_field_values(source, field, log_empty: false) if source.respond_to?(:champs) && source != @dossier
    return champs_to_values(champs) if champs.present?

    # from dossier champs
    champs = object_field_values(@dossier, field, log_empty: false)
    champs_to_values(champs).presence || [par_defaut]
  end

  def humanize(value)
    case value
    when DateTime
      value.strftime('%d/%m/%Y à %H:%M')
    when Date
      value.strftime('%d/%m/%Y')
    else
      value.to_s
    end
  end
end
