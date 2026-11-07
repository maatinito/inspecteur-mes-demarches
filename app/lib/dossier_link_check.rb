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

  # champs_identiques : champ du dossier => champ du dossier lié qui doit avoir
  # la même valeur, ex. { "Numéro DN": "Numéro DN" }. Un champ vide ou masqué
  # sur le dossier n'est pas comparé.
  def authorized_fields
    super + %i[champs_identiques message_champs_differents]
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

      next unless champs_identiques?(dossier, champ)
      next if champ.dossier.state != 'en_construction'

      if on_error?(champ.string_value.to_i)
        message = "Pour pouvoir traiter ce dossier, le dossier '#{label}' doit être corrigé."
        add_message(label, champ.string_value, message)
      end
    end
  end

  def on_error?(dossier_number)
    Message.joins(:check).where(checks: { dossier: dossier_number }).any?
  end

  private

  def champs_identiques?(dossier, lien)
    (@params[:champs_identiques] || {}).all? do |champ, champ_lie|
      valeur = valeur_comparable(dossier_field(dossier, champ.to_s, warn_if_empty: false))
      next true if valeur.blank?

      valeur_liee = valeur_comparable(dossier_field(lien.dossier, champ_lie.to_s, warn_if_empty: false))
      next true if valeur == valeur_liee

      message = @params[:message_champs_differents] || "ne correspond pas à celui du dossier #{lien.string_value}"
      add_message(champ.to_s, valeur, "#{message} (#{champ_lie} : #{valeur_liee.presence || 'non renseigné'})")
      false
    end
  end

  # Numéro DN : le numéro seul (sans la date de naissance) ; espaces et casse ignorés.
  def valeur_comparable(champ)
    return nil if champ.nil?

    valeur = champ.__typename == 'NumeroDnChamp' ? champ.numero_dn : champ_value(champ)
    valeur.to_s.gsub(/\s/, '').upcase
  end
end
