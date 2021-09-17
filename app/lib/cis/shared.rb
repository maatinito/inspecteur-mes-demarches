module Cis
  module Shared

    private

    def check_employee_age(line)
      #birthday is already normalized by super class
      birthday = line[:date_de_naissance]
      age = Time.zone.today.year - birthday.year
      age -= 1 if Time.zone.today < birthday + age.years
      return true if (18..62) === age

      "#{@params[:message_age]}: #{age}"
    end
  end
end
