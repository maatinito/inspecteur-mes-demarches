# frozen_string_literal: true

module Spjp
  class Amount < Daf::Amount
    include ActionView::Helpers::NumberHelper
    def version
      super + 1
    end

    def required_fields
      super + %i[prix_avec_electricite prix_sans_electricite]
    end

    def initialize(params)
      super
      @source = @params[:champs_source]
      prices_with_electricity = @params[:prix_avec_electricite]
      prices_with_electricity = prices_with_electricity.split(',').map(&:strip).map(&:to_i) if prices_with_electricity.is_a?(String)
      prices_without_electricity = @params[:prix_sans_electricite]
      prices_without_electricity = prices_without_electricity.split(',').map(&:strip).map(&:to_i) if prices_without_electricity.is_a?(String)
      @prices = {
        true => prices_with_electricity,
        false => prices_without_electricity
      }
    end

    def process_row(_row, output)
      bill = compute_bill
      output['Commandes'] = bill
      output['Montant HT'] = bill.map { |line| line['montant'] }.sum
    end

    private

    def compute_bill
      annotation(@source).rows.map do |order|
        sites = object_field_values(order, 'Zone').first&.values || []
        tables = object_field_values(order, 'Tables').first&.values || []
        days = object_field_values(order, 'Nombre de jours').first&.value.to_i
        half_days = object_field_values(order, 'Nombre de demi-journées').first&.value.to_i
        hours = object_field_values(order, "Nombre d'heures").first&.value.to_i
        electricity = object_field_values(order, 'Avec électricité').first&.value

        prices = unit_prices(order)
        amount = total(days, half_days, hours, prices, order)
        durations = durations(days, half_days, hours)
        label = bill_label(electricity, sites, tables)

        bill_order(label, durations, amount)
      end
    end

    def total(days, half_days, hours, prices, order)
      non_profit = object_field_values(order, 'Non lucratif').first&.value
      rate = non_profit ? 0.2 : 1
      price_for_one_site = ((hours * prices[0]) + (half_days * prices[1]) + (days.positive? ? prices[2] + (prices[3] * (days - 1)) : 0))
      sites = object_field_values(order, 'Zone').first&.values || []
      (rate * sites.size * price_for_one_site).round
    end

    def durations(days, half_days, hours)
      [hours, half_days, days].zip(%w[heure demi-journée jour]).map { |nb, unit| "#{nb.humanize} #{unit}#{'s' if nb > 1}" if nb.positive? }
    end

    def bill_order(label, durations, amount)
      {
        'libelle' => label,
        'duree' => durations.filter(&:present?).join(', '),
        'montant' => amount,
        'montant_en_chiffres' => number_to_currency(amount, unit: '', separator: ',', delimiter: ' ', precision: 0)
      }
    end

    def bill_label(electricity, sites, tables)
      electricity_s = electricity ? 'avec electricité' : 'sans electricité'
      "#{sites.join(', ')} (#{tables.join(', ')}#{', ' if tables.size.positive?}#{electricity_s})"
    end

    # There's two set of prices, with and without eletricity
    # One set of price includes price for hours, hald-days, first day, next days
    # If there are tables on a particular site and only a subset of the three tables are reserved,
    # price is proportional to number of reserved tables
    def unit_prices(order)
      # prices are different if electricity is provided or not
      electricity = object_field_values(order, 'Avec électricité').first.value
      # prices are for three tables and must be divided if only one or two tables are booked
      tables_nb = object_field_values(order, 'Tables').first&.values&.size || 3
      @prices[electricity].map { |price| (1..2).include?(tables_nb) ? (price / 3.0) * tables_nb : price }
    end

    def amount
      compute_bill.map { |line| line['montant'] }.sum
    end
  end
end
