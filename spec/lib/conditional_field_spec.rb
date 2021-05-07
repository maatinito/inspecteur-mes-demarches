# frozen_string_literal: true

require 'rails_helper'
require 'inspector_task'

RSpec.describe ConditionalField do
  let(:controle) { FactoryBot.build :protocole_sanitaire }
  subject do
    DossierActions.on_dossier(dossier_nb) do |dossier|
      controle.control(dossier)
      pp controle
      pp dossier
    end
    controle
  end

  context 'everything is ok', vcr: { cassette_name: 'meme_demandeur_ok' } do
    let(:dossier_nb) { 40_045 }

    it 'no error message' do
      expect(subject.messages).to be_empty
    end
  end

  context 'immunise without attached document', vcr: { cassette_name: 'condition_field_77456' } do
    let(:dossier_nb) { 77_456 }
    let(:message) do
      FactoryBot.build :message, field: controle.params[:valeurs]['Immunisé'][0]['mandatory_field_check']['message'], value: 'vide', message: 'm1'
    end

    it "have one error on Schema d'immunisation" do
      expect(subject.messages.size).to be 1
      expect(subject.messages.first).to eq message
    end
  end
end
