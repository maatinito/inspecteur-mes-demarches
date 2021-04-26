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

  def check(dossier)
    fields = param_values(:champ)
    fields.each do |field|
      case field.__typename
      when 'TextChamp', 'IntegerNumberChamp','DecimalNumberChamp'
        if normalize(field&.value) != @params[:value]
          add_message(@params[:champ], field.value, @params[:message] + ': ' + @params[:valeur])
        end
      end
    end
  end

  private

  def normalize(v)
    v&.to_s&.parameterize&.delete('-')
  end
end