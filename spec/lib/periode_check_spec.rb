require 'rails_helper'

VCR.use_cassette('mes_demarches') do
  DemarcheActions.get_demarche(217, 'DESETI', 'clautier@idt.pf')

  RSpec.describe PeriodeCheck do
    context 'initialization', vcr: { cassette_name: 'periode_check' } do
      context 'all good' do
        let(:controle) { FactoryBot.build :periode_check, :for_deseti }
        it 'must be valid' do
          expect(controle.valid?).to be true
        end
      end

      context 'periode bad value' do
        let(:controle) { FactoryBot.build :periode_check, :for_deseti, periode: "7" }
        it 'must be invalid' do
          expect(controle.valid?).to be_falsey
        end
      end
    end

    context 'deseti' do
      let(:controle) { FactoryBot.build :periode_check, :for_deseti }
      subject do
        DossierActions.on_dossier(dossier_nb) do |dossier|
          controle.check(dossier)
          # pp controle
          # pp dossier
        end
        controle
      end

      context 'everything is ok', vcr: { cassette_name: 'periode_check_53992' } do
        let(:dossier_nb) { 53_992 }

        it 'no error message' do
          expect(subject.messages).to be_empty
        end
      end
    end

    context 'RES Quarantaine' do
      let(:controle) { FactoryBot.build :periode_check, :for_res }
      subject do
        DossierActions.on_dossier(dossier_nb) do |dossier|
          controle.check(dossier)
          # pp controle
          # pp dossier
        end
        controle
      end

      context 'with error messages', vcr: { cassette_name: 'periode_check_54045' } do
        let(:dossier_nb) { 54_045 }
        let(:field) { "#{controle.params[:champ_debut]}..#{controle.params[:champ_fin]}"}
        let(:value1) { "01/10/2020..08/10/2020=8 jours"}
        let(:value2) { "01/10/2020..10/10/2020=10 jours"}
        let(:message1) { FactoryBot.build :message, field: field, value: value1, message: controle.params[:message] }
        let(:message2) { FactoryBot.build :message, field: field, value: value2, message: controle.params[:message] }
        it 'triggered' do
          expect(subject.messages).to eq [message1, message2]
        end
      end
    end
  end
end
