# frozen_string_literal: true

require 'rails_helper'

VCR.use_cassette('mes_demarches') do
  DemarcheActions.get_demarche(217, 'DESETI', 'clautier@idt.pf')

  RSpec.describe Deseti::Instruction do
    let(:demarche) { DemarcheActions.get_demarche(113, 'DESETI', 'clautier@idt.pf') }
    let(:passer_en_instruction) { instance_double(DossierPasserEnInstruction) }
    let(:task) { FactoryBot.build :deseti_instruction }
    let(:operation_passer_en_instruction) { instance_double(DossierPasserEnInstruction) }
    let(:operation_classer_sans_suite) { instance_double(DossierClasserSansSuite) }
    let(:operation_when_en_construction) { instance_double(DossierRefuser) }
    let(:operation_when_en_instruction) { instance_double(DossierRefuser) }
    let(:operation_when_refuse) { instance_double(DossierRefuser) }
    let(:operation_when_sans_suite) { instance_double(DossierClasserSansSuite) }

    before do
      passer_en_instruction_class = class_double('DossierPasserEnInstruction').as_stubbed_const
      allow(passer_en_instruction_class).to receive(:new).and_return(operation_passer_en_instruction)

      classer_sans_suite_class = class_double('DossierClasserSansSuite').as_stubbed_const
      allow(classer_sans_suite_class).to receive(:new).and_return(operation_classer_sans_suite, operation_when_sans_suite)

      refuser_class = class_double('DossierRefuser').as_stubbed_const
      allow(refuser_class).to receive(:new).and_return(
        operation_when_en_construction,
        operation_when_en_instruction,
        operation_when_refuse
      )
    end
    # commented because vcr didn't store the right requests
    # context 'Deseti accepted, activity stopped', vcr: { cassette_name: 'deseti_instruction_as' } do
    #   let(:dossier_nb) { 40_056 }
    #
    #   it 'should put dossier en_instruction' do
    #     expect(operation_passer_en_instruction).to receive(:process).once
    #     expect(task.errors).to be_empty
    #     expect(task.valid?).to be true
    #     task.process(demarche, dossier_nb)
    #   end
    # end

    context 'Deseti accepted, activity resumed', vcr: { cassette_name: 'deseti_instruction_ar' } do
      let(:dossier_nb) { 40_059 }

      it 'should dismiss the dossier' do
        expect(operation_passer_en_instruction).to receive(:process).once
        expect(operation_classer_sans_suite).to receive(:process).once
        expect(task.valid?).to be true
        task.process(demarche, dossier_nb)
      end
    end

    context 'Deseti refused, activity stopped', vcr: { cassette_name: 'deseti_instruction_rs' } do
      let(:dossier_nb) { 40_060 }

      it 'should refuse the dossier' do
        expect(operation_passer_en_instruction).to receive(:process).once
        expect(operation_when_refuse).to receive(:process).once
        expect(task.valid?).to be true
        task.process(demarche, dossier_nb)
      end
    end

    context 'Deseti css, activity stopped', vcr: { cassette_name: 'deseti_instruction_cs' } do
      let(:dossier_nb) { 40_061 }

      it 'should refuse the dossier' do
        expect(operation_passer_en_instruction).to receive(:process).once
        expect(operation_when_sans_suite).to receive(:process).once
        expect(task.valid?).to be true
        task.process(demarche, dossier_nb)
      end
    end

    context 'Deseti en_construction, activity stopped', vcr: { cassette_name: 'deseti_instruction_ds' } do
      let(:dossier_nb) { 40_062 }

      it 'should refuse the dossier' do
        expect(operation_passer_en_instruction).to receive(:process).once
        expect(operation_when_en_construction).to receive(:process).once
        expect(task.valid?).to be true
        task.process(demarche, dossier_nb)
      end
    end

    context 'Deseti en_instruction, activity stopped', vcr: { cassette_name: 'deseti_instruction_is' } do
      let(:dossier_nb) { 40_063 }

      it 'should refuse the dossier' do
        expect(operation_passer_en_instruction).to receive(:process).once
        expect(operation_when_en_instruction).to receive(:process).once
        expect(task.valid?).to be true
        task.process(demarche, dossier_nb)
      end
    end
  end
end
