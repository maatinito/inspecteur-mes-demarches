require 'set'

class FieldChecker

  attr_reader :messages

  attr_reader :accessed_fields

  attr_reader :errors

  def initialize(params)
    @errors        = []
    @params        = params.symbolize_keys
    missing_fields = (required_fields - @params.keys)
    @errors << "Les champs #{missing_fields.join(',')} devrait être définis sur #{self.class.name.underscore}" if missing_fields.present?
    unknown_fields = @params.keys - authorized_fields - required_fields
    @errors << "#{unknown_fields.join(',')} n'existe(nt) pas sur #{self.class.name.underscore}" if unknown_fields.present?
    @messages        = []
    @accessed_fields = Set[]
  end

  def valid?
    @errors.blank?
  end

  def control(dossier)
    @messages = []
    check(dossier)
  end

  def check(_dossier)
    raise "Should be implemented by class #{self}"
  end

  def field(dossier, field)
    @accessed_fields.add(field)
    objects = [*dossier]
    field.split(/\./).each do |name|
      objects = objects.flat_map { |object| object.champs.select { |champ| champ.label == name } }
    end
    objects
  end

  def add_message(champ, valeur, message)
    @messages << Message.new(field: champ, value: valeur, message: message)
  end

  def required_fields
    []
  end

  def authorized_fields
    []
  end

  def version
    1.0
  end
end
