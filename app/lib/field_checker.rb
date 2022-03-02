# frozen_string_literal: true

require 'set'

class FieldChecker < InspectorTask
  attr_reader :messages, :accessed_fields, :dossier, :modified_dossiers

  attr_writer :demarche

  def control(dossier)
    @messages = []
    @modified_dossiers = []
    @dossier = dossier
    check(dossier)
  end

  def must_check?(md_dossier)
    md_dossier&.state == 'en_construction'
  end

  def check(_dossier)
    raise "Should be implemented by class #{self}"
  end

  def fields(name, warn_if_empty: true)
    dossier_fields(@dossier, name, warn_if_empty: warn_if_empty)
  end

  def field(name, warn_if_empty: true)
    fields(name, warn_if_empty: warn_if_empty)&.first
  end

  def annotations(name, warn_if_empty: true)
    dossier_annotations(@dossier, name, warn_if_empty: warn_if_empty)
  end

  def annotation(name, warn_if_empty: true)
    annotations(name, warn_if_empty: warn_if_empty)&.first
  end

  def param_fields(param_name, warn_if_empty: true)
    fields(@params[param_name], warn_if_empty: warn_if_empty)
  end

  def param_field(param_name, warn_if_empty: true)
    param_fields(param_name, warn_if_empty: warn_if_empty)&.first
  end

  def param_annotations(param_name, warn_if_empty: true)
    annotations(@params[param_name], warn_if_empty: warn_if_empty)
  end

  def param_annotation(param_name, warn_if_empty: true)
    param_annotations(param_name, warn_if_empty: warn_if_empty)&.first
  end

  def dossier_field(dossier, name, warn_if_empty: true)
    dossier_fields(dossier, name, warn_if_empty: warn_if_empty)&.first
  end

  def dossier_fields(dossier, path, warn_if_empty: true)
    return nil if dossier.nil? || path.blank?

    objects = [*dossier]
    path.split(/\./).each do |name|
      objects = objects.flat_map { |object| object.champs.select { |champ| champ.label == name } }
      Rails.logger.warn("Sur le dossier #{dossier.number}, le champ #{name} est vide.") if warn_if_empty && objects.blank?
    end
    objects
  end

  def dossier_annotations(dossier, path, warn_if_empty: true)
    return nil if dossier.nil? || path.blank?

    names = path.split(/\./)
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

  def object_field_values(source, field, log_empty)
    objects = [*source]
    field.split(/\./).each do |name|
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

  def add_message(champ, valeur, message)
    @messages << Message.new(field: champ, value: valeur, message: message)
  end

  def annotation_updated_on(dossier)
    @modified_dossiers << dossier unless @modified_dossiers.any? { |d| d.number == dossier.number }
  end
end
