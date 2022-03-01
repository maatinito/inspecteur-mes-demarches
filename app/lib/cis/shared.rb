# frozen_string_literal: true

module Cis
  module Shared
    private

    def check_employee_age(line)
      # birthday is already normalized by super class
      birthday = line[:date_de_naissance] || line['Date de naissance']
      age = Time.zone.today.year - birthday.year
      age -= 1 if Time.zone.today < birthday + age.years
      return true if (18..62).include?(age)

      "#{@params[:message_age]}: #{age}"
    end

    CIS_DEMANDES_FIELD = 'Nombre de CIS demandés'

    def check_cis_demandes(cis_nb)
      in_dossier = field(CIS_DEMANDES_FIELD)&.value&.to_i
      return true if in_dossier == cis_nb

      message = @params[:message_cis_demandes] ||
        'Le nombre de cis demandes doit être égal au nombre de candidats dans le fichier Excel: '
      add_message(CIS_DEMANDES_FIELD, in_dossier, "#{message}: #{cis_nb}")
    end
  end
end
