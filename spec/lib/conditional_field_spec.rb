# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConditionalField do
  let(:controle) { FactoryBot.build :cis_association }
  subject do
    DossierActions.on_dossier(dossier_nb) do |dossier|
      controle.control(dossier)
    end
    controle
  end

  context 'cis for association', vcr: { cassette_name: 'condition_field_296392' } do
    let(:dossier_nb) { 296_392 }
    let(:messages) do
      ['Statuts à jour', 'Composition du bureau', "Déclaration de l'association"].map do |field|
        FactoryBot.build(:message, field:, message: controle.params[:valeurs]['920'][0]['mandatory_field_check']['message'], value: 'vide')
      end
    end

    it 'should have association fields filled' do
      expect(subject.messages).to eq messages
    end
  end
end
