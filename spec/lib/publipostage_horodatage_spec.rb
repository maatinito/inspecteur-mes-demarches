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

    it 'réutilise le même horodatage pour le nom du fichier envoyé' do
      travel_to(Time.zone.local(2026, 10, 2, 14, 35, 59)) { publipostage.send(:add_volatile_fields, {}) }
      travel_to(Time.zone.local(2026, 10, 2, 14, 36, 5)) do
        expect(publipostage.send(:horodatage)).to eq('2026-10-02 14h35')
      end
    end

    it 'prend l’heure courante si aucun document n’a encore été généré' do
      travel_to(Time.zone.local(2026, 10, 2, 9, 5, 0)) do
        expect(publipostage.send(:horodatage)).to eq('2026-10-02 09h05')
      end
    end
  end
end
