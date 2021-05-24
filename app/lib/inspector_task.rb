# frozen_string_literal: true

class InspectorTask
  attr_reader :errors, :params
  attr_accessor :name

  def initialize(params)
    @errors = []
    @params = params.symbolize_keys
    missing_fields = (required_fields - @params.keys)
    @errors << "Les champs #{missing_fields.join(',')} devrait être définis sur #{self.class.name.underscore}" if missing_fields.present?
    unknown_fields = @params.keys - authorized_fields - required_fields
    @errors << "#{unknown_fields.join(',')} n'existe(nt) pas sur #{self.class.name.underscore}" if unknown_fields.present?
    @messages = []
    @accessed_fields = Set[]
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
    name.gsub(/^[0-9]+:/,'')
  end
end
