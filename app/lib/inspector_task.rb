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
    return if valid?

    puts "Erreur à l'initialisation d'une tache"
    puts @errors
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

  def tap_name(name)
    @name = name
    self
  end

  def version
    @params_version ||= @params.values.reduce(Digest::SHA1.new) { |d, s| d << s.to_s }.hexdigest.to_i(16) % (2 << 31)
    1 + @params_version
  end

  def self.create_tasks(elements)
    return [] if elements.blank?

    elements.flatten.map.with_index do |description, i|
      create_task(description, i)
    end.flatten
  end

  def self.create_task(description, position)
    if description.is_a?(String)
      Object.const_get(description.camelize).new({}).tap_name("#{position}:#{description}")
    else
      # hash
      description.map { |taskname, params| Object.const_get(taskname.camelize).new(params).tap_name("#{position}:#{taskname}") }
    end
  end
end
