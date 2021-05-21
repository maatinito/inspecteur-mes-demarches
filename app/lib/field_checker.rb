# frozen_string_literal: true

require 'set'

class FieldChecker < InspectorTask
  attr_reader :messages, :accessed_fields, :dossier

  attr_writer :demarche

  def control(dossier)
    @messages = []
    @dossier = dossier
    check(dossier)
  end

  def must_check?(md_dossier)
    md_dossier&.state == 'en_construction'
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

  def field_values(field)
    return nil if @dossier.nil? || field.blank?

    objects = [*@dossier]
    field.split(/\./).each do |name|
      objects = objects.flat_map { |object| object.champs.select { |champ| champ.label == name } }
      Rails.logger.warn("Sur le dossier #{@dossier.number}, le champ #{field} est vide.") if objects.blank?
    end
    objects
  end

  def field_value(field_name)
    field_values(field_name)&.first
  end

  def param_values(param_name)
    field_values(@params[param_name])
  end

  def param_value(param_name)
    param_values(param_name)&.first
  end

  def add_message(champ, valeur, message)
    @messages << Message.new(field: champ, value: valeur, message: message)
  end

  def version
    1.0 + @params.hash
  end
end
