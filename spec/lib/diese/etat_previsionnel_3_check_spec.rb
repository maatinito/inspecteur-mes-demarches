# frozen_string_literal: true

require 'rails_helper'

FIELD_NAMES = [
  'Nombre de salariés DiESE au mois ',
  'Montant prévisionnel du DiESE au mois '
].freeze

SUMS = [
  [4, 405_867],
  [1, 147_456]
].freeze

LM = [
  ['Mauvais DDN', :message_date_de_naissance, '4504780,1965-05-24'],
  ['Mauvais DN', :message_dn, '1234567,1980-09-11']
].freeze

RATES = [70, 50, 40].freeze

def new_message(field, value, message_type, correction)
  pp controle.params, message_type, 'impossible de trouver' if controle.params[message_type].nil?
  msg = controle.params[message_type]
  msg += ": #{correction}" if correction.present?
  FactoryBot.build :message, field: field, value: value, message: msg
end

def field_name(base, index)
  "#{base}#{index + 1}"
end

RSpec.describe Diese::EtatPrevisionnel3Check do
  context 'DNs, sum copies are wrong' do
    let(:controle) { FactoryBot.build :diese_etat_previsionnel_3_check }
    let(:report_messages) do
      (0..SUMS.length - 1).flat_map do |m|
        [FactoryBot.build(:message, field: field_name(field, m), value: 'Mauvais Taux', message: "message_taux_depasse#{RATES[m]}%")] +
          FIELD_NAMES.each_with_index.map do |_name, i|
            value = (10 * (1 + m)) + i # 10,11,  20, 21
            new_message(field_name(FIELD_NAMES[i], m), value, :message_different_value, SUMS[m][i])
          end
      end
    end
    let(:field) { 'Etat nominatif des salariés/Mois ' }
    let(:rate_message) do
      FactoryBot.build :message, field: field_name(field, 2), value: 'Mauvais Taux', message: 'message_taux_depasse40%'
    end
    let(:dn_messages) { LM.map { |msg| new_message(field_name(field, 0), msg[0], msg[1], msg[2]) } }
    let(:messages) { dn_messages + report_messages + [rate_message] }

    subject do
      DossierActions.on_dossier(dossier_nb) do |dossier|
        controle.control(dossier)
      end
      controle
    end

    context 'Diese 3', vcr: { cassette_name: 'diese_3_181958' } do
      let(:dossier_nb) { 181_958 }

      it 'should trigger error messages' do
        expect(subject.messages).to eq messages
      end
    end

    # context 'Diese 3 Renouvellement', vcr: { cassette_name: 'diese_3_171825' } do
    #   let(:dossier_nb) { 171_825 }
    #
    #   it 'should trigger error messages' do
    #     expect(subject.messages).to eq messages
    #   end
    # end
  end
end
