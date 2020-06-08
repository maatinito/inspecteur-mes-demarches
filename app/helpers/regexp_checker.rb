
class DateDeNaissance < FieldChecker
  def initialize(params)
    super(params)
    if params.key?(:regex_aide) ^ params.key?(:message_aide)
      @errors << 'regex_aide et regex_message doivent être tous les deux définis'
    end
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
        next if /#{@params[:regex]}/ =~ champ.value

        message = params[:message]
        aides = champ.value.scan(/#{@params[:regex_aide]}/)
        if aides.present?
          message = message + @params[:message_aide] + aides.joins(',')
        end
        add_message(champ.libelle, champ.value, message)
      end
    end
  end
end
