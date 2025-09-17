# frozen_string_literal: true

module Cis
  module Shared
    CIS_DEMANDES_FIELD = 'Nombre de CIS demandés'

    private

    def check_employee_age(line)
      # birthday is already normalized by super class
      birthday = line[:date_de_naissance] || line['Date de naissance']
      return true if birthday.blank?

      age = Time.zone.today.year - birthday.year
      age -= 1 if Time.zone.today < birthday + age.years
      return true if (18..62).include?(age)

      "#{@params[:message_age]}: #{age}"
    end

    def check_cis_demandes(cis_nb)
      in_dossier = field(CIS_DEMANDES_FIELD)&.value&.to_i
      return true if in_dossier == cis_nb

      message = @params[:message_cis_demandes] ||
                'Le nombre de cis demandes doit être égal au nombre de candidats dans le fichier Excel: '
      add_message(CIS_DEMANDES_FIELD, in_dossier, "#{message}: #{cis_nb}")
    end

    def get_values_of(source, key, field, par_defaut = nil)
      return par_defaut unless field

      # from computed values
      value = @computed[key] if @computed.is_a? Hash
      return [*value] if value.present?

      # from excel source
      value = source[key] if source.is_a? Hash
      return [*value] if value.present?

      # from dossier champs
      champs = object_field_values(@dossier, field, log_empty: false)
      champs_to_values(champs).presence || [par_defaut]
    end

    def instanciate(template, source = nil)
      template.gsub(/{[^{}]+}/) do |matched|
        variable = matched[1..-2]
        get_values_of(source, variable, variable, '').first
      end
    end

    def build_filename(template, source = nil)
      return 'document.pdf' if template.blank?

      instanciate(template, source).gsub(/[^- 0-9a-z\u00C0-\u017F.]/i, '_')
    end
  end
end
