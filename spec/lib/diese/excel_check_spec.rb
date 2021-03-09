# frozen_string_literal: true

require 'rails_helper'

FIELD_NAMES = [
  'Nombre de salariés DiESE au mois M',
  "Montant intermédiaire de l'aide au mois M",
  'Montant du complément au titre du revenu plancher au mois M',
  'Montant total du DiESE au mois M'
].freeze

SUMS = [
  [12, 454_268, 7_559, 461_827],
  [11, 423_500, 7_559, 431_059],
  [10, 363_500, 7_559, 371_059]
].freeze

pp ActiveSupport::Dependencies.autoload_paths

LM = [
  ['Mauvaise DMO', :message_dmo, nil],
  ['Mauvais DN', :message_dn, '1234567,13/06/1985'],
  ['Mauvaise DDN', :message_date_de_naissance, '2214605,13/07/1985']
].freeze

def new_message(field, value, message_type, correction)
  pp controle.params, message_type, 'impossible de trouver' if controle.params[message_type].nil?
  msg = controle.params[message_type]
  msg += ": #{correction}" if correction.present?
  FactoryBot.build :message, field: field, value: value, message: msg
end

def field_name(base, index)
  index > 0 ? "#{base}+#{index}" : base
end

RSpec.describe Diese::ExcelCheck do
  context 'Renouvellement' do
    let(:controle) { FactoryBot.build :diese_excel_check, offset: 3 }
    subject do
      DossierActions.on_dossier(dossier_nb) do |dossier|
        controle.control(dossier)
      end
      controle
    end

    # commented because vcr didn't store the right requests

    # context 'DNs, sum copies, user are wrong', vcr: { cassette_name: 'diese_excel_check_48289' } do
    #   let(:dossier_nb) { 48_289 } # 46_761
    #   let(:libelle) { "#{controle.params[:message_mauvais_demandeur]}:378208" }
    #   let(:report_messages) do
    #     (3..5).flat_map do |m|
    #       FIELD_NAMES.each_with_index.map do |_name, i|
    #         value = (6 + m) * (10**i) # 9, 90, 900, 9000 then 10, 100, 1000, 1000, ...
    #         new_message(field_name(FIELD_NAMES[i], m), value, :message_different_value, SUMS[m - 3][i])
    #       end
    #     end
    #   end
    #   let(:field) { 'Etat nominatif des salariés/Mois M' }
    #   let(:dn_messages) { (3..5).flat_map { |i| LM.map { |msg| new_message(field_name(field, i), msg[0], msg[1], msg[2]) } } }
    #   let(:messages) { [*dn_messages, *report_messages] }
    #
    #   it 'have error messages' do
    #     pp subject.messages
    #     expect(subject.messages).to eq messages
    #   end
    # end

    context 'Excel file has missing column', vcr: { cassette_name: 'diese_excel_check_49792' } do
      let(:dossier_nb) { 49_772 }
      let(:field) { 'Etat nominatif des salariés' }
      let(:value) { 'Etat nominatif DiESE_teav-sept.xlsx' }
      let(:messages) { [new_message(field, value, :message_colonnes_manquantes, 'Nom de famille, Nom marital, Date de naissance')] }

      it 'have one error message' do
        pp subject.messages
        expect(subject.messages).to eq messages
      end
    end

    context 'Excel file has empty "nom de famille"', vcr: { cassette_name: 'diese_excel_check_49594' } do
      let(:dossier_nb) { 49_594 }
      let(:messages) { [] }

      it 'have one error message' do
        pp subject.messages
        expect(subject.messages).to eq messages
      end
    end
  end

  context 'On Nouveau Secteurs procedure,' do
    let(:controle) { FactoryBot.build :diese_excel_check, offset: 0 }
    subject do
      DossierActions.on_dossier(dossier_nb) do |dossier|
        controle.control(dossier)
      end
      controle
    end

    context 'DNs, sum copies, user are wrong,', vcr: { cassette_name: 'diese_excel_check_52481' } do
      let(:dossier_nb) { 52_481 }
      let(:report_messages) do
        (0..2).flat_map do |m|
          FIELD_NAMES.each_with_index.map do |_name, i|
            value = (2 + m) * (10 ** i) # 2,20,200,2000, 3,30,300,3000 ...
            new_message(field_name(FIELD_NAMES[i], m), value, :message_different_value, SUMS[m - 3][i])
          end
        end
      end
      let(:field) { 'Etat nominatif des salariés/Mois M' }
      let(:dn_messages) { (0..2).flat_map { |i| LM.map { |msg| new_message(field_name(field, i), msg[0], msg[1], msg[2]) } } }
      let(:messages) { [*dn_messages, *report_messages] }

      it 'should trigger error messages' do
        pp subject.messages
        expect(subject.messages).to eq messages
      end
    end
  end
end
