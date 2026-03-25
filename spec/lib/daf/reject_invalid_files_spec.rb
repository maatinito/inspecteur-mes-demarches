# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Daf::RejectInvalidFiles do
  def make_rows(count)
    count.times.map do
      double('Row', champs: [double('Champ', label: 'Nom', value: 'Test', __typename: 'TextChamp')])
    end
  end

  let(:demarche) { double('Demarche') }
  let(:dossier) do
    double('Dossier',
           number: 12_345,
           state: 'en_construction',
           champs: [repetition],
           annotations: [])
  end
  let(:repetition) do
    double('RepetitionChamp',
           __typename: 'RepetitionChamp',
           label: 'Demandes',
           rows: make_rows(row_count))
  end

  subject do
    controle.process(demarche, dossier)
    controle
  end

  context 'When dossier has too much requests' do
    let(:row_count) { 3 }
    let(:controle) { FactoryBot.build :reject_invalid_files, quand_invalide: [{ 'when_task' => {} }] }

    it 'task is called' do
      expect_any_instance_of(WhenTask).to receive(:process)
      subject
    end
  end

  context 'When dossier has good number of requests' do
    let(:row_count) { 2 }
    let(:controle) { FactoryBot.build :reject_invalid_files, :max10, quand_invalide: [{ 'when_task' => {} }] }

    it 'task is not called' do
      expect_any_instance_of(WhenTask).not_to receive(:process)
      subject
    end
  end
end
