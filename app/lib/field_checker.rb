# frozen_string_literal: true

require 'set'

class FieldChecker < InspectorTask
  attr_reader :messages, :accessed_fields

  attr_writer :demarche

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

  def version
    1.0
  end
end
