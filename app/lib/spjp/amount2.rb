# frozen_string_literal: true

module Spjp
  class Amount2 < Daf::Amount
    include ActionView::Helpers::NumberHelper

    def version
      super + 1
    end

    def required_fields
      super + %i[prix_avec_electricite prix_sans_electricite champs_zones_sans_electricite champs_zones_avec_electricite champ_non_lucratif]
    end

    WITH_ELECTRICITY = 'avec electricité'

    WITHOUT_ELECTRICITY = 'sans électricité'

    def initialize(params)
      super
      @zone_fields = {
        WITH_ELECTRICITY => to_array(@params[:champs_zones_avec_electricite]),
        WITHOUT_ELECTRICITY => to_array(@params[:champs_zones_sans_electricite])
      }
      @duration_fields = @params[:champs_source]
      @duration_fields = @duration_fields.split(',').map(&:strip) if @duration_fields.is_a?(String)
      raise "l'attribut champs_durees doit définir trois noms de champs (Nombre de d'heures, Nombre de demi-journées, Nombre de jours)" if @duration_fields.size != 3

      @prices = {
        WITH_ELECTRICITY => to_array(@params[:prix_avec_electricite]),
        WITHOUT_ELECTRICITY => to_array(@params[:prix_sans_electricite])
      }

      @zone_fields_prices = @zone_fields.zip(@prices)

      @champ_non_lucratif = @params[:champ_non_lucratif]
    end

    def process_row(row, output)
      @dossier = row
      bill = compute_bill
      output['Commandes'] = bill
      output['Montant HT'] = bill.map { |line| line['montant'] }.sum.round
    end

    private

    def to_array(string_or_array)
      string_or_array.is_a?(String) ? string_or_array.split(',').map(&:strip) : string_or_array
    end

    def compute_bill
      prices = unit_prices
      durations = @duration_fields.map { |field| annotation(field).value.to_i }
      @zone_fields.flat_map do |electricity, fields|
        fields.flat_map do |field|
          sites = field(field, warn_if_empty: false)&.values || []
          sites.map do |site|
            bill_order(bill_label(electricity, site), duration_label(durations), total(site, durations, prices[electricity]))
          end
        end
      end
    end

    def unit_prices
      non_lucrative = annotation(@champ_non_lucratif)&.value || false
      non_lucrative ? @prices.transform_values { |v| v.map { |p| p * 0.2 } } : @prices
    end

    def total(site, durations, prices)
      hours, half_days, days = durations
      price_for_one_site = ((hours * prices[0]) + (half_days * prices[1]) + (days.positive? ? prices[2] + (prices[3] * (days - 1)) : 0))
      (site.include?('Table') ? (price_for_one_site / 3.0) : price_for_one_site)
    end

    def duration_label(durations)
      durations.zip(%w[heure demi-journée jour]).filter_map { |nb, unit| "#{nb.humanize} #{unit}#{'s' if nb > 1}" if nb.positive? }.join(', ')
    end

    def bill_order(label, duration_label, amount)
      {
        'libelle' => label,
        'duree' => duration_label,
        'montant' => amount,
        'montant_en_chiffres' => number_to_currency(amount.round, unit: '', separator: ',', delimiter: ' ', precision: 0)
      }
    end

    def bill_label(electricity, site)
      "#{site}, #{electricity}"
    end

    def amount
      compute_bill.map { |line| line['montant'] }.sum.round
    end
  end
end
