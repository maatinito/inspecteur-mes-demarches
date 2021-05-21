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
    fields = param_values(:champ)
    fields.each do |field|
      case field.__typename
      when 'TextChamp', 'IntegerNumberChamp', 'DecimalNumberChamp'
        add_message(@params[:champ], field.value, "#{@params[:message]}: #{@params[:valeur]}") if normalize(field&.value) != @params[:value]
      end
    end
  end

  private

  def normalize(value)
    value&.to_s&.parameterize&.delete('-')
  end
end
