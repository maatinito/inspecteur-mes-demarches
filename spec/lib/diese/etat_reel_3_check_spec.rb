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

RSpec.describe Diese::EtatReel3Check do
  let(:controle) { FactoryBot.build :diese_etat_reel_3_check }

  subject do
    DossierActions.on_dossier(dossier_nb) do |dossier|
      controle.control(dossier)
    end
    controle
  end

  context 'Excel file has missing column', vcr: { cassette_name: 'diese_3_1_196370' } do
    let(:dossier_nb) { 196_370 }
    let(:value) { 'DiESE 3.1 Etat Reel Septembre Test Royal Tahitien.xlsx' }
    let(:field) { 'Etat nominatif actualisé/Etat' }
    let(:rate_message) do
      FactoryBot.build :message, field: field, value: 'Mauvais Taux', message: 'message_taux_depasse70%'
    end

    let(:dn_messages) { LM.map { |msg| new_message(field, msg[0], msg[1], msg[2]) } }
    let(:messages) { dn_messages + [rate_message] }

    it 'should trigger error messages' do
      expect(subject.messages).to eq messages
    end
  end
end
