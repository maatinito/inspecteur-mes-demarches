# frozen_string_literal: true

class NumeroDn < FieldChecker
  def initialize(params)
    super
    @cps = Cps::API.new
  end

  def required_fields
    %i[champ message_format_dn message_dn message_format_ddn message_ddn]
  end

  def authorized_fields
    []
  end

  def check(dossier)
    puts "Dossier #{dossier.number}"
    champs = dossier_fields(dossier, @params[:champ])
    puts "#{dossier.number} #{champs}"
    if champs.present?
      champs.map do |champ|
        puts "#{champ.numero_dn}:#{champ.date_de_naissance}"
        status = verify(champ.numero_dn, champ.date_de_naissance)
        add_message(@params[:champ], "#{champ.numero_dn}:#{champ.date_de_naissance}", @params[status]) if status != :good_dn
      end
    end
  end

  private

  def verify(dn, date)
    return :message_format_dn if dn !~ /\d{7}/

    begin
      date = Date.parse(date)
    rescue StandardError
      return :message_format_ddn
    end
    result = @cps.verify({ dn => date })
    puts result
    puts '--------------------------'
    case result[dn]
    when 'true'
      :good_dn
    when 'false'
      :message_ddn
    else
      :message_dn
    end
  end
end
