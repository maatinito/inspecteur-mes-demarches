# frozen_string_literal: true

class FieldValueCheck < FieldChecker
  def version
    super + 4
  end

  def required_fields
    super + %i[message champ valeur]
  end

  def initialize(params)
    super
    @params[:value] = normalize(@params[:valeur]) if @params.key?(:valeur)
  end

  def check(_dossier)
    fields = param_fields(:champ)
    fields.each do |field|
      value = case field.__typename
              when 'TextChamp' then field.value
              when 'IntegerNumberChamp' then field.int_value
              when 'DecimalNumberChamp' then field.decimal_value
              end
      next if value.nil?

      add_message(@params[:champ], value, "#{@params[:message]}: #{@params[:valeur]}") if normalize(value) != @params[:value]
    end
  end

  private

  def normalize(value)
    value&.to_s&.parameterize&.delete('-') # rubocop:disable Style/SafeNavigationChainLength
  end
end
