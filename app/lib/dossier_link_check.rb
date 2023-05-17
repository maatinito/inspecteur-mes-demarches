# frozen_string_literal: true

require 'tempfile'
require 'open-uri'
require 'roo'

class DossierLinkCheck < FieldChecker
  def version
    super + 3
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
    raise StandardError, "Le champ #{@params[:champ]} n'existe pas sur le dossier #{dossier.number}" if champs.blank?

    champs.each do |champ|
      label = champ.label
      unless champ.dossier.present?
        add_message(label, champ.string_value, "Le dossier #{champ.string_value} est introuvable")
        next
      end

      demarche_number = champ.dossier&.demarche&.number
      unless demarche_number.present? && @demarches.include?(demarche_number)
        add_message(label, champ.string_value, @params[:message_mauvaise_demarche])
        next
      end

      next if champ.dossier.state != 'en_construction'

      if on_error(champ.string_value.to_i)
        message = "Pour pouvoir traiter ce dossier, le dossier '#{label}' doit être corrigé."
        add_message(label, champ.string_value, message)
      end
    end
  end

  def on_error(dossier_number)
    Message.joins(:check).where(checks: { dossier: dossier_number }).count.positive?
  end
end
