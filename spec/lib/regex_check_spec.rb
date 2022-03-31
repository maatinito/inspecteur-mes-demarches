# frozen_string_literal: true

require 'rails_helper'

def re_new_message(field, value, correction)
  msg = controle.params[:message]
  msg += controle.params[:message_aide] + ": #{correction}" if correction.present?
  FactoryBot.build :message, field: field, value: value, message: msg
end

RSpec.describe RegexCheck do
  context 'initialization', vcr: { cassette_name: 'regex_check' } do
    context 'all good' do
      let(:controle) { FactoryBot.build :regex_check, :for_no_tahiti_iti }
      it 'must be valid' do
        expect(controle.valid?).to be true
      end
    end
  end

  subject do
    DossierActions.on_dossier(dossier_nb) do |dossier|
      controle.control(dossier)
    end
    controle
  end

  context 'Tahiti Iti number too short', vcr: { cassette_name: 'regex_check_71828' } do
    let(:controle) { FactoryBot.build :regex_check, :for_no_tahiti_iti }
    let(:dossier_nb) { 71_828 }
    let(:field) { 'Numéro Tahiti ITI' }
    let(:value) { '007120' }
    let(:messages) { [re_new_message(field, value, nil)] }

    it 'has one error message' do
      expect(subject.messages).to eq messages
    end
  end

  context 'Tahiti Iti number with -', vcr: { cassette_name: 'regex_check_296392' } do
    let(:controle) { FactoryBot.build :regex_check, :for_no_tahiti_iti }
    let(:dossier_nb) { 296_392 }
    let(:field) { 'Numéro Tahiti ITI' }
    let(:value) { 'C28723-001' }
    let(:messages) { [re_new_message(field, value, '-')] }

    it 'has one error message' do
      expect(subject.messages).to eq messages
    end
  end
end
