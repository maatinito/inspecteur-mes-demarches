# frozen_string_literal: true

require 'rails_helper'

def new_message(field, value, message_type, correction)
  pp controle.params, message_type, 'impossible de trouver' if controle.params[message_type].nil?
  msg = controle.params[message_type]
  msg += ": #{correction}" if correction.present?
  FactoryBot.build :message, field: field, value: value, message: msg
end

def field_name(base, index)
  index > 0 ? "#{base}+#{index}" : base
end

RSpec.describe Cis::EtatPrevisionnelCheck do
  context 'depot' do
    let(:controle) { FactoryBot.build :cis_etat_previsionnel_check, offset: 3 }
    subject do
      DossierActions.on_dossier(dossier_nb) do |dossier|
        controle.control(dossier)
      end
      controle
    end

    context 'Excel file has errors', vcr: { cassette_name: 'cis_etat_previsionnel_check_71723' } do
      let(:dossier_nb) { 71_723 }
      let(:field) { 'État nominatif des demandeurs/Stagiaires' }
      let(:messages) do
        [
          new_message(field, 'Erreur DN', :message_dn, '1234567,1979-12-11'),
          new_message(field, 'Erreur DDN', :message_date_de_naissance, '2464292,1979-12-12'),
          new_message(field, 'Erreur NiveauEtudeVide', :message_colonnes_vides, 'niveau_etudes'),
          new_message(field, 'Erreur CiviliteVide', :message_colonnes_vides, 'civilite'),
          new_message(field, 'Erreur DN Conjoint', :message_dn, '1234567,1979-12-11'),
          new_message(field, 'Erreur DDN Conjoint', :message_date_de_naissance, '2464292,1979-12-12'),
          new_message(field, 'Erreur ActiviteVide', :message_colonnes_vides, 'activite'),
          new_message('Nombre de CIS demandés', '3', :message_cis_demandes, '10')
        ]
      end

      it ' has error messages ' do
        expect(subject.messages).to eq messages
      end
    end
  end
end
