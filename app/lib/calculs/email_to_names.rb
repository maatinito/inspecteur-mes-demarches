# frozen_string_literal: true

module Calculs
  class EmailToNames < FieldChecker
    include ActionView::Helpers::NumberHelper

    MAIL_REGEX = /(?<name>[^@]+)@/
    NAMES_REGEX = /(?<firstname>[^.]+)\.(?<lastname>.+)/

    def version
      super + 1
    end

    def authorized_fields
      super + %i[mails fonction_par_défaut]
    end

    def process_row(dossier, output)
      instructeur_email = dossier.instructeurs.first&.email
      handle(output, 'Instructeur', instructeur_email)
      dossier.annotations.filter { |c| c.__typename == 'VisaChamp' }.each { |champ| handle(output, champ.label, champ.string_value) }
      dossier.annotations.filter { |c| c.__typename == 'TextChamp' && c.value.is_a?(String) && c.value.match?(URI::MailTo::EMAIL_REGEXP) }.each { |champ| handle(output, champ.label, champ.value) }
    end

    def handle(output, variable, valeur)
      return unless (match = valeur&.downcase&.match(MAIL_REGEX))

      v1 = "#{variable}.prénom"
      v2 = "#{variable}.nom"
      v3 = "#{variable}.fonction"
      name = match[:name].gsub(/[\p{L}\p{M}]+/u, &:capitalize)
      user_definition = @params[:mails]&.[](match[:name])
      if user_definition.present?
        (output[v1], output[v2], output[v3]) = user_definition.split(/\s*,\s*/)
      elsif (match = name.match(NAMES_REGEX))
        output[v1] = normalize(match[:firstname])
        output[v2] = normalize(match[:lastname])
        output[v3] = @params[:fonction_par_défaut] || ''
      else
        output[v1] = normalize(name)
        output[v2] = ''
        output[v3] = @params[:fonction_par_défaut] || ''
      end
    end

    def normalize(name)
      name.gsub(/[_.]/, ' ')
    end
  end
end
