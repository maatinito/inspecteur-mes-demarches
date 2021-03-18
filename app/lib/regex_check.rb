# frozen_string_literal: true

class RegexCheck < FieldChecker
  def version
    super + 1
  end

  def initialize(params)
    super(params)
    @errors << 'regex_aide et regex_message doivent être tous les deux définis' if params.key?(:regex_aide) ^ params.key?(:message_aide)
  end

  def required_fields
    %i[champ message regex]
  end

  def authorized_fields
    %i[regex_aide message_aide]
  end

  def check(dossier)
    champs = field(dossier, @params[:champ])
    if champs.present?
      champs.map do |champ|
        next if champ.value.strip.match?(/^#{@params[:regex]}$/)

        message = params[:message]
        if @params[:message_aide].present? && @params[:regex_aide].present?
          aides = champ.value.scan(/#{@params[:regex_aide]}/)
          message = message + @params[:message_aide] + ': ' + aides.join(',') if aides.present?
        end
        add_message(champ.label, champ.value, message)
      end
    end
  end
end
