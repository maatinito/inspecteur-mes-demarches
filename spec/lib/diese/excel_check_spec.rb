# frozen_string_literal: true

require 'spec_helper'

FIELD_NAMES = [
  'Nombre de salariés DiESE au mois M+',
  "Montant intermédiaire de l'aide au mois M+",
  'Montant du complément au titre du revenu plancher au mois M+',
  'Montant total du DiESE au mois M+'
].freeze

SUMS = [
  [12, 491_602, 0, 491_602],
  [11, 460_834, 0, 460_834],
  [10, 400_834, 0, 400_834]
].freeze

DN = [
  ['Mauvais DN', :message_dn, '1234567,13/06/1985'],
  ['Mauvaise DDN', :message_date_de_naissance, '2214605,13/07/1985']
].freeze

def new_message(field, value, message_type, correction)
  pp controle.params, message_type, 'impossible de trouver' if controle.params[message_type].nil?
  msg = controle.params[message_type]
  msg += ': ' + correction.to_s if correction.present?
  FactoryBot.build :message, field: field, value: value, message: msg
end

VCR.use_cassette('diese_excel_check') do
  RSpec.describe Diese::ExcelCheck do
    let(:demarche) { DemarcheActions.get_demarche(459, 'DIESE', 'clautier@idt.pf') }
    let(:controle) { FactoryBot.build :diese_excel_check }
    subject do
      DossierActions.on_dossier(dossier_nb) do |dossier|
        controle.check(dossier)
      end
      controle
    end

    context 'DNs, sum copies, user are wrong', vcr: { cassette_name: 'diese_excel_check_wrong_dossier' } do
      let(:dossier_nb) { 46_761 }
      let(:libelle) { "#{controle.params[:message_mauvais_demandeur]}:378208" }
      let(:report_messages) do
        (3..5).flat_map do |m|
          FIELD_NAMES.each_with_index.map do |_name, i|
            value = (6 + m) * (10**i) # 9, 90, 900, 9000 then 10, 100, 1000, 1000, ...
            new_message(FIELD_NAMES[i] + m.to_s, value, :message_different_value, SUMS[m - 3][i])
          end
        end
      end
      let(:field) { 'Etat nominatif des salariés/Mois M+' }
      let(:dn_messages) { (3..5).flat_map { |i| DN.map { |msg| new_message(field + i.to_s, msg[0], msg[1], msg[2]) } } }
      let(:messages) { [*dn_messages, *report_messages] }

      it 'have error messages' do
        pp subject.messages
        expect(subject.messages).to eq messages
      end
    end

    context 'Excel file has missing column', vcr: { cassette_name: 'diese_excel_colonne_manquante' } do
      let(:dossier_nb) { 49_772 }
      let(:field) { 'Etat nominatif des salariés' }
      let(:value) { 'Etat nominatif DiESE_teav-sept.xlsx' }
      let(:messages) { [new_message(field, value, :message_colonnes_manquantes, 'Date de naissance')] }

      it 'have one error message' do
        pp subject.messages
        expect(subject.messages).to eq messages
      end
    end
  end
end
