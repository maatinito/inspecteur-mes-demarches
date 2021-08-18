# frozen_string_literal: true

class InspectorTask
  attr_reader :errors, :params, :name
  attr_accessor :demarche

  def initialize(params)
    @errors = []
    @params = params.symbolize_keys
    missing_fields = (required_fields - @params.keys)
    @errors << "Les champs #{missing_fields.join(',')} devrait être définis sur #{self.class.name.underscore}" if missing_fields.present?
    unknown_fields = @params.keys - authorized_fields - required_fields
    @errors << "#{unknown_fields.join(',')} n'existe(nt) pas sur #{self.class.name.underscore}" if unknown_fields.present?
    @messages = []
    @accessed_fields = Set[]
    unless valid?
      puts "Erreur à l'initialisation d'une tache"
      puts @errors
    end
  end

  def valid?
    @errors.blank?
  end

  def required_fields
    []
  end

  def authorized_fields
    []
  end

  def old_name
    name.gsub(/^[0-9]+:/, '')
  end

  def set_name(name)
    @name = name
    self
  end
end
