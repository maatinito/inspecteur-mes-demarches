# frozen_string_literal: true

require 'rails_helper'

FIELD_NAMES = [
  'Nombre de salariés DiESE au mois ',
  'Montant prévisionnel du DiESE au mois '
].freeze

SUMS = [
  [3, 370_810],
  [1, 230_686]
].freeze

LM = [
  ['Colonnes Vides', :message_colonnes_vides, 'heure_avant_convention,brut_mensuel_moyen,heures_a_realiser,dmo'],
  ['Mauvais DDN', :message_date_de_naissance, '4504780,1965-05-24'],
  ['Mauvais DN', :message_dn, '1234567,1980-09-11']
].freeze

def new_message(field, value, message_type, correction)
  pp controle.params, message_type, 'impossible de trouver' if controle.params[message_type].nil?
  msg = controle.params[message_type]
  msg += ": #{correction}" if correction.present?
  FactoryBot.build :message, field: field, value: value, message: msg
end

def field_name(base, index)
  "#{base}#{index + 1}"
end

RSpec.describe Diese::EtatReelCheck do

  let(:controle) { FactoryBot.build :diese_etat_reel_check }

  subject do
    DossierActions.on_dossier(dossier_nb) do |dossier|
      controle.control(dossier)
    end
    controle
  end

  context 'Excel file has missing column', vcr: { cassette_name: 'diese_2.1_84172' } do
    let(:dossier_nb) { 84_172 }
    let(:field) { 'Etat nominatif actualisé' }
    let(:value) { 'CSE v2 Etat Réel - SOCREDO - MC.xlsx' }
    let(:messages) { [new_message(field, value, :message_colonnes_manquantes, 'aide maximale')] }

    it 'has one error message' do
      expect(subject.messages).to eq messages
    end
  end

  context 'Diese Reel', vcr: { cassette_name: 'diese_2.1_84165' } do
    let(:dossier_nb) { 84_165 }
    let(:field) { 'Etat nominatif des salariés/Mois ' }
    let(:messages) { LM.map { |msg| new_message('Etat nominatif actualisé/Etat', msg[0], msg[1], msg[2]) } }

    it 'should trigger error messages' do
      expect(subject.messages).to eq messages
    end
  end
end
