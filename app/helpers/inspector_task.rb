class InspectorTask
  attr_reader :errors

  def initialize(params)
    @errors = []
    @params = params.symbolize_keys
    missing_fields = (required_fields - @params.keys)
    if missing_fields.present?
      @errors << "Les champs #{missing_fields.join(',')} devrait être définis sur #{self.class.name.underscore}"
    end
    unknown_fields = @params.keys - authorized_fields - required_fields
    if unknown_fields.present?
      @errors << "#{unknown_fields.join(',')} n'existe(nt) pas sur #{self.class.name.underscore}"
    end
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
end
