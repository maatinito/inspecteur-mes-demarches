# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PublipostageV2 do
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
    let(:controle) { FactoryBot.build :publipostage_v2, :docx, :store_to_field }
    it 'should be valid' do
      expect(controle.valid?).to be_truthy
    end
  end

  context 'store docx to root field' do
    let(:generated_path) { "tmp/publipost/publipostage v2 #{dossier_nb}.docx" }
    before do
      allow(controle).to receive(:delete)
      allow(SetAnnotationValue).to receive(:set_piece_justificative)
    end
    after { FileUtils.rm_f(generated_path) }

    context 'with perfect variables' do
      let(:controle) { FactoryBot.build :publipostage_v2, :docx, :store_to_field }
      it 'generate docx', vcr: { cassette_name: 'publipostage_v2-1' } do
        subject

        doc = Docx::Document.open(generated_path)
        expect(doc.to_html).to include('NAVIRE')
        expect(doc.to_html).to include('05/05/2023')
        expect(doc.tables.size).to eq(2)
        expect(doc.tables[0].rows.map { |row| row.cells.map(&:text) })
          .to eq([['Libellé des produits', 'Poids', 'Code'],
                  ['Libellé : Ailes de poulet', '40.5', '1002'],
                  ['Libellé : Cuisses de canard', '13.8', '3002'],
                  ['Libellé : Bœuf', '555', '4005']])
        expect(doc.tables[1].rows.map { |row| row.cells.map(&:text) })
          .to eq([['Libellé des produits', 'Poids', 'Code'],
                  ['Cuisses de poulets', '314.0', '2022'],
                  ['Porc', '333.0', '3033']])
      end
    end

    context 'with unknown variables or tables' do
      let(:controle) { FactoryBot.build :publipostage_v2, :docx, :store_to_field, :model_with_errors }
      it 'generate docx', vcr: { cassette_name: 'publipostage_v2-1' } do
        subject

        doc = Docx::Document.open(generated_path)
        expect(doc.to_html).to include('NAVIRE')
        expect(doc.to_html).to include('05/05/2023')
        expect(doc.tables.size).to eq(2)
        expect(doc.tables[0].rows.map { |row| row.cells.map(&:text) }).to eq([['Libellé des produits', 'Poids', 'Code'], ['Libellé : --Libellé des produits--', '--Poids--', '--Mauvais Code--']])
        expect(doc.tables[1].rows.map do |row|
          row.cells.map(&:text)
        end).to eq([['Libellé des produits', 'Poids', 'Code'], ['Cuisses de poulets', '314.0', '--Mauvais Code--'], ['Porc', '333.0', '--Mauvais Code--']])
      end
    end
  end
end
