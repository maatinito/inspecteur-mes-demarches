# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Cis::EtatReelV2Check do
  let(:controle) { FactoryBot.build :cis_etat_reel_v2_check }
  subject do
    DossierActions.on_dossier(dossier_nb) do |dossier|
      controle.control(dossier)
    end
    controle
  end

  context 'Excel file', vcr: { cassette_name: 'cis_etat_reel_v2_check_295695' } do
    let(:dossier_nb) { 295_695 }
    let(:field) { 'Relevé des absences' }
    let(:sheet_field) { "#{field}/Personnes" }
    let(:filename) { 'Relevé des absences Mai 2022 nettoyage des plages Tombeau du roi_ vaipoopoo et lafayette.xlsx' }
    let(:messages) do
      [
        new_message(sheet_field, 'MANARII Vairea Lucia', :message_absence),
        new_message(sheet_field, 'Personne En trop', :message_dn, '4567897,1973-06-28'),
        new_message(sheet_field, 'Personne En trop', :message_absence),
        new_message(field, filename, :message_personnes_manquantes, 'Ruta Juliette TERAI'),
        new_message(field, filename, :message_personnes_inconnues, 'En trop Personne')
      ]
    end

    it 'have error messages' do
      expect(subject.messages).to eq messages
    end
  end
end
