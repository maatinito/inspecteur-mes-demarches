class DateDeNaissance < FieldChecker

  def version
    1.5
  end

  def initialize(params)
    super(params)
    if @params[:age] !~ /\d+\.\.\d+/
      @errors << "#{@params[:age]}: Pour une date de naissance, spécifiez l'age sous forme d'intervalle x..y"
    end
  end

  def required_fields
    %i[champ message age]
  end

  def authorized_fields
    []
  end

  def check(dossier)
    champs = field(dossier, @params[:champ])
    if champs.present?
      champs.map do |champ|
        date = Date.parse(champ.value)
        unless range.cover?(date)
          add_message(@params[:champ],date, @params[:message])
        end
      end
    end
  end

  private

  def range
    match = @params[:age].match(/(\d+)..(\d+)/)
    debut = Time.zone.now - match[2].to_i.years
    fin   = Time.zone.now - match[1].to_i.years
    (debut..fin)
  end
end
