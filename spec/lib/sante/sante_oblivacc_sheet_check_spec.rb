# frozen_string_literal: true

require 'rails_helper'

def new_message(field, value, message_type, correction)
  pp controle.params, message_type, 'impossible de trouver' if controle.params[message_type].nil?
  msg = controle.params[message_type]
  msg += ": #{correction}" if correction
  FactoryBot.build :message, field: field, value: value, message: msg
end

def field_name(base, index)
  index > 0 ? "#{base}+#{index}" : base
end

RSpec.describe Sante::OblivaccSheetCheck do
  context 'depot' do
    let(:controle) { FactoryBot.build :sante_oblivacc_sheet_check }
    subject do
      DossierActions.on_dossier(dossier_nb) do |dossier|
        controle.control(dossier)
      end
      controle
    end

    context 'Excel file has errors', vcr: { cassette_name: 'sante_oblivacc_sheet_check_200894' } do
      let(:dossier_nb) { 200_894 }
      let(:field) { 'Personnes/Liste personnes concernées' }
      let(:messages) do
        [
          new_message(field, 'Manutea GAY', :message_date_de_naissance, '2208097,1981-04-13'),
          new_message(field, 'Arthur Conan', :message_dn, '1234567,1958-05-15'),
          new_message(field, 'Incomplet Incomplet', :message_format_dn,''),
          new_message(field, 'Incomplet Incomplet', :message_colonnes_vides, 'date_de_naissance,activite'),
        ]
      end

      it ' has error messages ' do
        expect(subject.messages).to eq messages
      end
    end
  end
end
