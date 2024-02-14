# frozen_string_literal: true

module Calculs
  class EmailToNames < FieldChecker
    include ActionView::Helpers::NumberHelper

    MAIL_REGEX = /(?<name>[^.]+)@/
    NAMES_REGEX = /(?<firstname>[^.]+)\.(?<lastname>.+)/

    def version
      super + 1
    end

    def authorized_fields
      super + %i[mails]
    end

    def process_row(dossier, output)
      instructeur_email = dossier.instructeurs.first&.email
      handle(output, 'Instructeur', instructeur_email)
      dossier.annotations.filter { |c| c.__typename == 'VisaChamp' }.each do |champ|
        handle(output, champ.label, champ.string_value)
      end
    end

    def handle(output, variable, valeur)
      return unless (match = valeur&.downcase&.match(MAIL_REGEX))

      v1 = "#{variable}.prénom"
      v2 = "#{variable}.nom"
      name = match[:name].gsub(/[\p{L}\p{M}]+/u, &:capitalize)
      user_definition = @params[:mails]&.[](match[:name])
      if user_definition.present?
        (output[v1], output[v2]) = user_definition.split(/\s*,\s*/)
      elsif (match = name.match(NAMES_REGEX))
        output[v1] = normalize(match[:firstname])
        output[v2] = normalize(match[:lastname])
      else
        output[v1] = normalize(name)
        output[v2] = ''
      end
    end

    def normalize(name)
      name.gsub(/[_.]/, ' ')
    end
  end
end
