# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Publipostage do
  let(:dossier_nb) { 338_356 }
  let(:dossier) { DossierActions.on_dossier(dossier_nb) }
  let(:demarche) { double(Demarche) }
  let(:instructeur) { 'instructeur' }

  before do
    allow(demarche).to receive(:instructeur).and_return(instructeur)
    allow(SendMessage).to receive(:send)
    allow(controle).to receive(:instructeur_id_for).and_return(1)
    file = "storage/publipost/#{dossier_nb}/publipostage #{dossier_nb}.yml"
    FileUtils.rm_f(file)
  end

  subject do
    controle.process(demarche, dossier)
    controle
  end

  context 'initialization' do
    let(:controle) { FactoryBot.build :publipostage, :docx, :store_to_field }
    it 'should be valid' do
      expect(controle.valid?).to be_truthy
    end
  end

  context 'generate docx' do
    let(:generated_path) { "tmp/publipost/publipostage #{dossier_nb}.docx" }
    before do
      allow(controle).to receive(:delete)
      expect(SetAnnotationValue).to receive(:set_piece_justificative_on_annotation)
    end
    after { FileUtils.rm_f(generated_path) }

    context 'on root field from dossier' do
      let(:controle) { FactoryBot.build :publipostage, :docx, :store_to_field }
      it 'generate docx', vcr: { cassette_name: 'publipostage-1' } do
        subject

        doc = Docx::Document.open(generated_path)
        expect(doc.to_html).to include('NAVIRE')
        expect(doc.to_html).to include('05/05/2023')
      end
    end

    context 'on repetition field from repetition' do
      let(:controle) { FactoryBot.build :publipostage, :docx, :on_repetition }
      it 'generate docx', vcr: { cassette_name: 'publipostage-1' } do
        subject

        doc = Docx::Document.open(generated_path).to_html
        expect(doc).to include('NAVIRE')
        expect(doc).to include('05/05/2023')
        expect(doc).to include('MOTIF')
      end
    end

    context 'on root field from repetition' do
      let(:controle) { FactoryBot.build :publipostage, :docx, :on_repetition, :store_to_field }
      it 'generate docx', vcr: { cassette_name: 'publipostage-1' } do
        subject

        doc = Docx::Document.open(generated_path).to_html
        expect(doc).to include('NAVIRE')
        expect(doc).to include('05/05/2023')
        expect(doc).to include('MOTIF')
      end
    end
  end
end
