# frozen_string_literal: true

require 'rails_helper'

FIELD_NAMES = [
  'Nombre de salariés CSE au mois ',
  'CSE brut mois ',
  'Cotisations mois '
].freeze

SUMS = [
  [2, 163_802, 51_893],
  [2, 163_802, 51_893],
  [2, 163_802, 51_893]
].freeze

LM = [
  ['DN (Nom) Julien', :message_date_de_naissance, '4504780,1965-05-24'],
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

RSpec.describe Cse::EtatPrevisionnelCheck do

  context 'DNs, sum copies are wrong' do
    let(:controle) { FactoryBot.build :cse_etat_previsionnel_check }
    let(:field) { 'Etat nominatif prévisionnel des salariés/Mois ' }
    let(:messages_3_5) do
      (3..5).flat_map do |m|
        LM.map { |msg| new_message(field_name(field, m), msg[0], msg[1], msg[2]) }
      end
    end
    let(:messages_0_2) do
      (0..2).flat_map do |m|
        LM.map { |msg| new_message(field_name(field, m), msg[0], msg[1], msg[2]) } +
          FIELD_NAMES.each_with_index.map do |_name, i|
            value = 10 * (1 + m) + i # 10,11,  20, 21
            new_message(field_name(FIELD_NAMES[i], m), value, :message_different_value, SUMS[m][i])
          end
      end
    end
    # let(:dn_messages) { (0..5).map { |i| LM.map { |msg| new_message(field_name(field, i), msg[0], msg[1], msg[2]) } } }
    let(:messages) { messages_0_2 + messages_3_5 }

    subject do
      DossierActions.on_dossier(dossier_nb) do |dossier|
        controle.control(dossier)
      end
      controle
    end

    context 'Cse', vcr: { cassette_name: 'cse_2.1_69001' } do
      let(:dossier_nb) { 69001 }

      it 'should trigger error messages' do
        expect(subject.messages).to eq messages
      end
    end

  end
end
