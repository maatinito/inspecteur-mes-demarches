# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Publipostage do
  include ActiveSupport::Testing::TimeHelpers

  let(:publipostage) { described_class.new({}) }

  describe 'variable volatile Horodatage' do
    it 'ajoute la date et l’heure de génération, heure de Tahiti' do
      travel_to(Time.zone.local(2026, 10, 2, 14, 35, 12)) do
        fields = {}
        publipostage.send(:add_volatile_fields, fields)
        expect(fields['Horodatage']).to eq('2026-10-02 14h35')
      end
    end

    it 'mémorise la valeur pour le {horodatage} du nom de fichier envoyé ensuite' do
      travel_to(Time.zone.local(2026, 10, 2, 14, 35, 59)) { publipostage.send(:add_volatile_fields, {}) }
      travel_to(Time.zone.local(2026, 10, 2, 14, 36, 5)) do
        expect(publipostage.instance_variable_get(:@horodatage)).to eq('2026-10-02 14h35')
      end
    end
  end
end
