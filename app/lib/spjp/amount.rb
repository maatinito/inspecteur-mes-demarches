# frozen_string_literal: true

module Spjp
  class Amount < Daf::Amount
    include ActionView::Helpers::NumberHelper
    def version
      super + 1
    end

    def required_fields
      super + %i[prix_avec_electricite prix_sans_electricite champs_zones champ_electricite champ_non_lucratif]
    end

    def initialize(params)
      super
      @zone_fields = @params[:champs_zones]
      @zone_fields = @zone_fields.split(',').map(&:strip) if @zone_fields.is_a?(String)

      @duration_fields = @params[:champs_source]
      @duration_fields = @duration_fields.split(',').map(&:strip) if @duration_fields.is_a?(String)
      raise "l'attribut champs_durees doit définir trois noms de champs (Nombre de d'heures, Nombre de demi-journées, Nombre de jours)" if @duration_fields.size != 3

      prices_with_electricity = @params[:prix_avec_electricite]
      prices_with_electricity = prices_with_electricity.split(',').map(&:strip).map(&:to_i) if prices_with_electricity.is_a?(String)
      prices_without_electricity = @params[:prix_sans_electricite]
      prices_without_electricity = prices_without_electricity.split(',').map(&:strip).map(&:to_i) if prices_without_electricity.is_a?(String)
      @prices = {
        true => prices_with_electricity,
        false => prices_without_electricity
      }
      @champ_electricite = @params[:champ_electricite]
      @champ_non_lucratif = @params[:champ_non_lucratif]
    end

    def process_row(row, output)
      @dossier = row
      bill = compute_bill
      output['Commandes'] = bill
      output['Montant HT'] = bill.map { |line| line['montant'] }.sum
    end

    private

    def compute_bill
      durations = @duration_fields.map { |field| annotation(field).value.to_i }
      electricity = field(@champ_electricite).value
      prices = unit_prices(electricity)
      @zone_fields.flat_map do |zone|
        sites = field(zone, warn_if_empty: false)&.values || []
        sites.map do |site|
          bill_order(bill_label(electricity, site), duration_label(durations), total(site, durations, prices))
        end
      end
    end

    def unit_prices(electricity)
      non_lucrative = annotation(@champ_non_lucratif).value
      @prices[electricity].map { |price| non_lucrative ? price * 0.2 : price }
    end

    def total(site, durations, prices)
      hours, half_days, days = durations
      price_for_one_site = ((hours * prices[0]) + (half_days * prices[1]) + (days.positive? ? prices[2] + (prices[3] * (days - 1)) : 0))
      (site.include?('Table') ? (price_for_one_site / 3) : price_for_one_site).round
    end

    def duration_label(durations)
      durations.zip(%w[heure demi-journée jour]).filter_map { |nb, unit| "#{nb.humanize} #{unit}#{'s' if nb > 1}" if nb.positive? }.join(', ')
    end

    def bill_order(label, duration_label, amount)
      {
        'libelle' => label,
        'duree' => duration_label,
        'montant' => amount,
        'montant_en_chiffres' => number_to_currency(amount, unit: '', separator: ',', delimiter: ' ', precision: 0)
      }
    end

    def bill_label(electricity, site)
      electricity_s = electricity ? 'avec electricité' : 'sans electricité'
      "#{site}, #{electricity_s}"
    end

    def amount
      compute_bill.map { |line| line['montant'] }.sum
    end
  end
end
