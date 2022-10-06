# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Cis::EtatReelCheck do
  context 'depot' do
    let(:controle) { FactoryBot.build :cis_etat_reel_check }
    subject do
      DossierActions.on_dossier(dossier_nb) do |dossier|
        controle.control(dossier)
      end
      controle
    end

    context 'Excel file has multiple errors"', vcr: { cassette_name: 'cis_etat_reel_check_295682' } do
      let(:dossier_nb) { 295_682 }
      let(:field) { 'État nominatif des demandeurs/Stagiaires' }
      let(:messages) do
        [
          new_message(field, 'Erreur DN', :message_dn, '1234567,1979-12-11'),
          new_message(field, 'Erreur DDN', :message_date_de_naissance, '2464292,1979-12-12'),
          new_message(field, 'Erreur Colonne vide', :message_colonnes_vides, 'absences')
        ]
      end

      it 'have one error message' do
        expect(subject.messages).to eq messages
      end
    end
  end
end
