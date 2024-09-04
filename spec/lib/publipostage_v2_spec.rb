# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PublipostageV2 do
  let(:dossier_nb) { 373_443 }
  let(:dossier) { DossierActions.on_dossier(dossier_nb) }
  let(:demarche) { double(Demarche) }
  let(:instructeur) { 'instructeur' }

  before do
    allow(demarche).to receive(:instructeur).and_return(instructeur)
    allow(SendMessage).to receive(:send)
    allow(controle).to receive(:instructeur_id_for).and_return(1)
    file = "storage/publipost/#{dossier_nb}/publipostage v2 #{dossier_nb}.yml"
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
    let(:marchandises) do
      [['Libellé des produits', 'Poids', 'Code'],
       ['Saucisses lentilles, parmentier, foie gras', '20.312', '1601-1602'],
       ['Prép. Alimentaires "Poisson"', '', '1604'],
       ['Aliments pour animaux', '6.942', '2309'],
       ['Saucisses lentilles, choucroute, confit', '19.384', '1601-1602'],
       ['Sauce nuoc mam', '', '2103'],
       ['Gâteau riz caramel, crème dessert', '9.216', '1901'],
       ['Aliments pour animaux', '8556.368', '2309']]
    end
    let(:marchandises_etiquetees) { marchandises.map.with_index { |line, i| [i > 0 ? "Libellé : #{line[0]}" : line[0], line[1], line[2]] } }

    before do
      FileUtils.rm_f(generated_path)
      allow(controle).to receive(:delete)
      expect(SetAnnotationValue).to receive(:set_piece_justificative_on_annotation)
    end
    after { FileUtils.rm_f(generated_path) }

    context 'with perfect variables' do
      let(:controle) { FactoryBot.build :publipostage_v2, :docx, :store_to_field }
      it 'generate docx', vcr: { cassette_name: 'publipostage_v2-1' } do
        subject

        doc = Docx::Document.open(generated_path)
        expect(doc.to_html).to include('NAVIRE')
        expect(doc.to_html).to include('UNAVIRE')
        expect(doc.to_html).to include('dnavire')
        expect(doc.to_html).to include('CNavire')
        expect(doc.to_html).to include('CcNavire')
        expect(doc.to_html).to include('05/05/2023')
        expect(doc.tables.size).to eq(4)
        expect(doc.tables[0].rows.map { |row| row.cells.map(&:text) }).to match(marchandises_etiquetees)
        expect(doc.tables[1].rows.map { |row| row.cells.map(&:text) }).to match(marchandises)
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
        msg = "La table a pour titre Produits mais aucun champ contenant une liste porte ce nom. Clés disponibles: Dossier, Navire, Date d'arrivée, Produits 1, Produits 2"
        expect(doc.tables[0].rows.map { |row| row.cells.map(&:text) })
          .to eq([[msg, 'Poids', 'Code'],
                  ['Libellé : --Libellé des produits--', '--Poids--', '--Mauvais Code--']])
        expect(doc.tables[1].rows.map { |row| row.cells.map(&:text) })
          .to eq(marchandises.map.with_index { |line, i| [line[0], line[1], i > 0 ? '--Mauvais Code--' : line[2]] })
      end
    end

    context 'with multiple sheets' do
      let(:controle) { FactoryBot.build :publipostage_v2, :docx, :store_to_field, :with_multiple_sheets }
      it 'generate docx', vcr: { cassette_name: 'publipostage_v2-1' } do
        subject

        doc = Docx::Document.open(generated_path)
        expect(doc.to_html).to include('NAVIRE')
        expect(doc.to_html).to include('05/05/2023')
        expect(doc.tables.size).to eq(4)
        expect(doc.tables[2].rows.map { |row| row.cells.map(&:text) })
          .to eq([['Libelle', 'Nom scientifique'],
                  ['Hetre', 'Hetrus bordus'],
                  ['Sapin', 'Sapinus']])
        expect(doc.tables[3].rows.map { |row| row.cells.map(&:text) })
          .to eq([['Libelle', 'Nom scientifique'],
                  ['Cepes', 'Cepinusetbordus'],
                  ['Truffe', 'TrouffiusLupinus']])
      end
    end
  end
end
