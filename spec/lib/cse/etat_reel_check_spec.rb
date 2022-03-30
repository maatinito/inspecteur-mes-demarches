# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Cse::EtatReelCheck do
  context 'depot' do
    let(:controle) { FactoryBot.build :cse_etat_reel_check }
    subject do
      DossierActions.on_dossier(dossier_nb) do |dossier|
        controle.control(dossier)
      end
      controle
    end

    context 'Excel file has missing column', vcr: { cassette_name: 'cse_etat_reel_check_69243' } do
      let(:dossier_nb) { 69_243 }
      let(:field) { 'Etat nominatif actualisé' }
      let(:value) { 'CSE v2 Etat Réel - SOCREDO - MC.xlsx' }
      let(:messages) { [new_message(field, value, :message_colonnes_manquantes, 'aide maximale')] }

      it 'has one error message' do
        pp subject.messages
        expect(subject.messages).to eq messages
      end
    end

    context 'Excel file has multiple errors"', vcr: { cassette_name: 'cse_etat_reel_check_69244' } do
      let(:dossier_nb) { 69_244 }
      let(:field) { 'Etat nominatif actualisé/Etat' }
      let(:ddn_value) { 'DN (Nom) Julien' }
      let(:secteur_value) { "Secteur d'activité en C8" }
      let(:messages) do
        [
          new_message(field, ddn_value, :message_date_de_naissance, '4504780,1965-05-24'),
          new_message(field, secteur_value, :message_secteur_activite, '')
        ]
      end

      it 'have one error message' do
        pp subject.messages
        expect(subject.messages).to eq messages
      end
    end
  end
end
