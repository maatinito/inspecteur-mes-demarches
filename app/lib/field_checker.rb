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

  def add_message(champ, valeur, message)
    @messages << Message.new(field: champ, value: valeur, message: message)
  end

  def version
    @params_version ||= @params.values.reduce(Digest::SHA1.new) { |d, s| d << s.to_s }.hexdigest.to_i(16) % (2 << 31)
    1 + @params_version
  end

  def annotation_updated_on(dossier)
    @modified_dossiers << dossier unless @modified_dossiers.any? { |d| d.number == dossier.number }
  end
end
