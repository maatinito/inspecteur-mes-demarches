# frozen_string_literal: true

require 'tempfile'
require 'open-uri'
require 'roo'

class DossierLinkCheck < FieldChecker
  def version
    super + 1
  end

  def required_fields
    %i[champ demarches message_mauvaise_demarche]
  end

  def initialize(params)
    super
    @demarches = Set.new(@params[:demarches])
  end

  def check(dossier)
    champs = dossier_fields(dossier, @params[:champ])
    puts "Le champ #{@params[:champ]} n'existe pas sur le dossier #{dossier.number}" if champs.blank?
    throw StandardError.new "Le champ #{@params[:champ]} n'existe pas sur le dossier #{dossier.number}" if champs.blank?

    champs.each do |champ|
      unless champ.dossier.present?
        add_message(@params[:champ], champ.string_value, "Le dossier #{champ.string_value} est introuvable")
        next
      end

      demarche_number = champ.dossier&.demarche&.number
      unless demarche_number.present? && @demarches.include?(demarche_number)
        add_message(@params[:champ], champ.string_value, @params[:message_mauvaise_demarche])
        next
      end
    end
  end
end
