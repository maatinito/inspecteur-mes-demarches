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

  context 'valid control' do
    let(:controle) { FactoryBot.build :publipostage, :docx, :store_to_field }
    it 'should be valid' do
      expect(controle.valid?).to be_truthy
    end
  end

  context 'store docx to root field' do
    let(:generated_path) { "tmp/publipost/publipostage #{dossier_nb}.docx" }
    before do
      allow(controle).to receive(:delete)
      allow(SetAnnotationValue).to receive(:set_piece_justificative)
    end
    after { FileUtils.rm_f(generated_path) }

    context 'with perfect variables' do
      let(:controle) { FactoryBot.build :publipostage, :docx, :store_to_field }
      it 'generate docx', vcr: { cassette_name: 'publipostage-1' } do
        subject

        doc = Docx::Document.open(generated_path)
        expect(doc.to_html).to include('NAVIRE')
        expect(doc.to_html).to include('05/05/2023')
      end
    end
  end
end
