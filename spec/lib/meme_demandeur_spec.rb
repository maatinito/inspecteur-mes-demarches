# frozen_string_literal: true

require 'rails_helper'
require 'inspector_task'

RSpec.describe MemeDemandeur do
  let(:controle) { FactoryBot.build :meme_demandeur }
  subject do
    DossierActions.on_dossier(dossier_nb) do |dossier|
      controle.control(dossier)
    end
    controle
  end

  context 'everything is ok', vcr: { cassette_name: 'meme_demandeur_ok' } do
    let(:dossier_nb) { 69_244 }

    it 'no error message' do
      expect(subject.messages).to be_empty
    end
  end

  context 'Numero Tahiti is wrong', vcr: { cassette_name: 'meme_demandeur_bad_tahiti' } do
    let(:dossier_nb) { 296_399 }
    let(:libelle) { "#{controle.params[:message_mauvais_demandeur]}:966705" }
    let(:message) { FactoryBot.build :message, field: controle.params[:champ], value: '69001', message: libelle }

    it 'have one error on Tahiti number' do
      expect(subject.messages.first).to eq message
    end
  end

  context 'Numero Tahiti & Numero Dossier are wrong', vcr: { cassette_name: 'meme_demandeur_bad_dossier' } do
    let(:dossier_nb) { 296_409 }
    let(:libelle1) { "#{controle.params[:message_mauvais_demandeur]}:966705" }
    let(:message1) { FactoryBot.build :message, field: controle.params[:champ], value: '296392', message: libelle1 }
    let(:libelle2) { controle.params[:message_mauvaise_demarche] }
    let(:message2) { FactoryBot.build :message, field: controle.params[:champ], value: '296392', message: libelle2 }

    it 'have 2 errors' do
      expect(subject.messages).to eq [message1, message2]
    end
  end
end
