# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConditionalField do
  let(:controle) { FactoryBot.build :repetition_count }
  subject do
    result = {}
    DossierActions.on_dossier(dossier_nb) do |dossier|
      controle.process_row(dossier, result)
    end
    result
  end

  context 'cis for association', vcr: { cassette_name: 'repetition_count_402509' } do
    let(:dossier_nb) { 402_509 }
    let(:count) { 2 }

    it 'should have association fields filled' do
      expect(subject['Demandes.count']).to eq count
      expect(subject['Demandes.nombre']).to eq count
      expect(subject['Commandes.count']).to eq count
      expect(subject['Commandes.nombre']).to eq count
    end
  end
end
