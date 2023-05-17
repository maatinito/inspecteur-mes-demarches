# frozen_string_literal: true

module Diese
  module RateCheck
    def rate_check_version
      3
    end

    def required_fields
      super + %i[message_taux_depasse]
    end

    def check(dossier)
      @must_check_rate = must_check_rate
      if @must_check_rate
        activity = activity_field
        @max_rates = RATES.dig(activity.primary_value, activity.secondary_value)
        raise "Secteur inconnu #{activity.primary_value};#{activity.secondary_value} dans le dossier #{dossier.number}" if @max_rates.blank?
      end
      super
    end

    private

    CHECKS = (EtatPrevisionnelCheck::CHECKS + %i[max_rate]).freeze

    RATES = {
      'Tourisme' => {
        'Hébergement touristique terrestre' => [70, 50, 40],
        'Meublés du tourisme' => [40, 40, 40],
        'Hébergement touristique flottant' => [70, 50, 40],
        'Prestataires touristiques et culturels' => [70, 60, 60]
      },
      "Autres secteurs d'activité éligibles" => {
        'Restauration' => [70, 50, 40],
        'Transport aérien' => [50, 40, 40],
        'Commerces et activités présents dans les hôtels' => [40, 40, 40],
        "Commerces et activités présents sur la plateforme aéroportuaire de Tahiti-Faa'a et dans les aérodromes des îles" => [50, 50, 50],
        "Bijouterie, artisanat d'art" => [80, 80, 80],
        'Boutiques de souvenirs et curios' => [80, 80, 80],
        'Perliculture' => [90, 90, 90],
        'Discothèques et assimilées' => [90, 90, 90],
        "Prestataires dans le domaine de l'évènementiel (foires, expositions, évènements sportifs, etc.)" => [90, 90, 90]
      }
    }.freeze

    def check_max_rate(line)
      return unless @must_check_rate

      value = line[:taux]
      value = value.to_f if value.is_a?(String)
      raise "Mois inconnu dans le dossier #{dossier.number}" if month.blank?

      max_rate = @max_rates[month]
      value <= (max_rate / 100.0) ? true : "#{@params[:message_taux_depasse]}#{max_rate}%"
    end

    def must_check_rate
      raise NotImplementedError, "must_check_rate must be implemented by class #{self.class.name}"
    end

    def month
      raise NotImplementedError, "month must be implemented by class #{self.class.name}"
    end
  end
end
