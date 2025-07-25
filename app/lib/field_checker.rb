# frozen_string_literal: true

require 'set'

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

    values.map { |v| v.is_a?(String) ? Date.iso8601(v) : v }
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
    return champ.strftime('%d/%m/%Y') if champ.is_a?(Date)
    return champ.to_s if champ.is_a? GraphQL::Client::Schema::EnumType::EnumValue
    return champ unless champ.respond_to?(:__typename) # direct value

    graphql_champ_value(champ)
  end

  def graphql_champ_value(champ)
    case champ.__typename
    when 'TextChamp', 'IntegerNumberChamp', 'DecimalNumberChamp', 'CheckboxChamp'
      champ.value || ''
    when 'CiviliteChamp'
      champ.value.to_s
    when 'MultipleDropDownListChamp'
      champ.values
    when 'LinkedDropDownListChamp'
      "#{champ.primary_value}/#{champ.secondary_value}"
    when 'DateTimeChamp'
      date_value(champ, '%d/%m/%Y %H:%M')
    when 'DateChamp'
      date_value(champ, '%d/%m/%Y')
    when 'NumeroDnChamp'
      "#{champ.numero_dn}|#{champ.date_de_naissance}"
    when 'DossierLinkChamp', 'SiretChamp', 'VisaChamp'
      champ.string_value
    when 'PieceJustificativeChamp'
      champ.files.map(&:filename).join(',')
    when 'TitreIdentiteChamp'
      "Titre d'identité"
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
    raise StandardError, d.errors if d.errors.present?

    d.data.dossier.instructeurs.first&.id
  end

  def instanciate(template, source = nil)
    template.gsub(/{(?:([^{};]*);)?([^{}]+?)(?:;([^{};]*))?}/) do |_matched|
      m = ::Regexp.last_match # 3 matches : prefix, variable name to look for and postfix
      value = get_values_of(source, m[2], '').join(', ')
      value.present? ? "#{m[1]}#{value}#{m[3]}" : ''
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
