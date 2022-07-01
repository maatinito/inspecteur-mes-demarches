# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Daf::RejectInvalidFiles do
  let(:dossier_nb) { 303_186 }

  context 'depot' do
    subject do
      DossierActions.on_dossier(dossier_nb) do |dossier|
        demarche = double('Demarche')
        controle.process(demarche, dossier)
      end
      controle
    end

    context 'When dossier has too much requests', vcr: { cassette_name: 'daf_reject_invalid_files_1' } do
      let(:controle) { FactoryBot.build :reject_invalid_files, quand_invalide: [{ 'when_task' => {} }] }

      it 'task is called' do
        expect_any_instance_of(WhenTask).to receive(:process)
        subject
      end
    end

    context 'When dossier has good number of ', vcr: { cassette_name: 'daf_reject_invalid_files_1' } do
      let(:controle) { FactoryBot.build :reject_invalid_files, :max10, quand_invalide: [{ 'when_task' => {} }] }

      it 'task is called' do
        expect_any_instance_of(WhenTask).not_to receive(:process)
        subject
      end
    end
  end
end
