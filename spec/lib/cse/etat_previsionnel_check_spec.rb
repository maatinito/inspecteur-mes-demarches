# frozen_string_literal: true

require 'rails_helper'

FIELD_NAMES = [
  'Nombre de salariés CSE au mois',
  'CSE brut mois',
  'Cotisations mois'
].freeze

SUMS = [
  [2, 163_802, 51_893],
  [2, 163_802, 51_893],
  [2, 163_802, 51_893]
].freeze

LM = [
  ['DN (Nom) Julien', :message_date_de_naissance, '4504780,1965-05-24']
].freeze

RSpec.describe Cse::EtatPrevisionnelCheck do
  context 'DNs, sum copies are wrong' do
    let(:controle) { FactoryBot.build :cse_etat_previsionnel_check }
    let(:field) { 'Etat nominatif prévisionnel des salariés/Mois' }
    let(:last_messages) do
      (3..5).flat_map do |m|
        LM.map { |msg| new_message(field_name(field, m+1), msg[0], msg[1], msg[2]) }
      end
    end
    let(:first_messages) do
      (0..2).flat_map do |m|
        LM.map { |msg| new_message(field_name(field, m+1), msg[0], msg[1], msg[2]) } +
          FIELD_NAMES.each_with_index.map do |_name, i|
            value = (10 * (1 + m)) + i # 10,11,  20, 21
            new_message(field_name(FIELD_NAMES[i], m+1), value, :message_different_value, SUMS[m][i])
          end
      end
    end
    # let(:dn_messages) { (0..5).map { |i| LM.map { |msg| new_message(field_name(field, i), msg[0], msg[1], msg[2]) } } }
    let(:messages) { first_messages + last_messages }

    subject do
      DossierActions.on_dossier(dossier_nb) do |dossier|
        controle.control(dossier)
      end
      controle
    end

    context 'Cse', vcr: { cassette_name: 'cse_2.1_69001' } do
      let(:dossier_nb) { 69_001 }

      it 'should trigger error messages' do
        expect(subject.messages).to eq messages
      end
    end
  end
end
