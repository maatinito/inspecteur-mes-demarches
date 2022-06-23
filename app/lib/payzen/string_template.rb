# frozen_string_literal: true

module Payzen
  module StringTemplate
    def instanciate(template, source = nil)
      template.gsub(/{[^{}]+}/) do |matched|
        variable = matched[1..-2]
        get_values_of(source, variable, '-').first
      end
    end

    def get_values_of(source, field, par_defaut = nil)
      return par_defaut unless field

      # from order
      value = humanize(source[field.to_sym]) if source.is_a? Hash
      return [*value] if value.present?

      # from dossier champs
      champs = object_field_values(@dossier, field, log_empty: false)
      champs_to_values(champs).presence || [par_defaut]
    end

    def humanize(value)
      case value
      when DateTime
        value.strftime('%d/%m/%Y à %H:%M')
      when Date
        value.strftime('%d/%m/%Y')
      else
        value.to_s
      end
    end
  end
end
