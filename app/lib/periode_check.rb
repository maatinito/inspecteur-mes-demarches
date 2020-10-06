# frozen_string_literal: true

class PeriodeCheck < FieldChecker
  def version
    1
  end

  def initialize(params)
    super(params)
    @errors << "#{@params[:periode]}: Spécifiez la période sous forme d'intervalle x..y" if @params[:periode] !~ /\d+\.\.\d+/
    @champ_debut = @params[:champ_debut]
    @champ_fin = @params[:champ_fin]
  end

  def required_fields
    %i[champ_debut champ_fin periode message]
  end

  def authorized_fields
    []
  end

  def check(dossier)
    periodes(dossier).map do |periode|
      debut, fin = periode
      if debut.blank?
        add_message(@champ_debut, "", @params[:message])
      elsif fin.blank?
        add_message(@champ_fin, "", @params[:message])
      else
        duration = (Date.parse(fin) - Date.parse(debut)).to_i + 1
        add_message("#{@champ_debut}..#{@champ_fin}", "#{f(debut)}..#{f(fin)}=#{duration} jours", @params[:message]) unless range.cover?(duration)
      end
    end
  end

  private

  def f(date)
    Date.parse(date).strftime('%d/%m/%Y')
  end

  def periodes(dossier)
    debuts = field(dossier, @champ_debut).map(&:value)
    fins = field(dossier, @champ_fin).map(&:value)
    debuts.zip(fins)
  end

  def range
    return @range if @range.present?
    match = @params[:periode].match(/(\d+)..(\d+)/)
    @range = (match[1].to_i..match[2].to_i)
  end
end
