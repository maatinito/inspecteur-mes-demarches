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

RSpec.describe Diese::EtatPrevisionnelCheck do
  context 'DNs, sum copies are wrong' do
    let(:controle) { FactoryBot.build :diese_etat_previsionnel_check }
    let(:report_messages) do
      (0..SUMS.length - 1).flat_map do |m|
        FIELD_NAMES.each_with_index.map do |_name, i|
          value = (10 * (1 + m)) + i # 10,11,  20, 21
          new_message(field_name(FIELD_NAMES[i], m), value, :message_different_value, SUMS[m][i])
        end
      end
    end
    let(:field) { 'Etat nominatif des salariés/Mois ' }
    let(:dn_messages) { LM.map { |msg| new_message(field_name(field, 0), msg[0], msg[1], msg[2]) } }
    let(:messages) { dn_messages + report_messages }

    subject do
      DossierActions.on_dossier(dossier_nb) do |dossier|
        controle.control(dossier)
      end
      controle
    end

    context 'Diese 2.1', vcr: { cassette_name: 'diese_2.1_84125' } do
      let(:dossier_nb) { 84_125 }

      it 'should trigger error messages' do
        expect(subject.messages).to eq messages
      end
    end

    context 'Diese 2.1 Renouvellement', vcr: { cassette_name: 'diese_2.1_84160' } do
      let(:dossier_nb) { 84_160 }

      it 'should trigger error messages' do
        expect(subject.messages).to eq messages
      end
    end
  end
end
