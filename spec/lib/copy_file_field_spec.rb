# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CopyFileField do
  let(:dossier_nb) { 441_984 }
  let(:dossier) { DossierActions.on_dossier(dossier_nb) }
  let(:demarche) { double(Demarche) }
  let(:instructeur) { 'instructeur' }

  subject do
    controle.process(demarche, dossier)
    controle
  end

  context 'initialization' do
    let(:controle) { FactoryBot.build :copy_file_field }
    it 'should be valid' do
      expect(controle.valid?).to be_truthy
    end
  end

  context 'generate pdf' do
    before do
      allow(controle).to receive(:delete)
      allow(demarche).to receive(:instructeur).and_return(instructeur)
      allow(controle).to receive(:instructeur_id_for).and_return(1)
    end

    context 'on one field', skip: 'waiting for Office suite' do
      let(:controle) { FactoryBot.build :copy_file_field }
      it 'store pdf', vcr: { cassette_name: 'copy_file_field-1' } do
        expect(SetAnnotationValue).to receive(:set_piece_justificative_on_annotation) do |_dossier, _instructeur, _annotation, path, filename|
          expect(filename).to match(/-[0-9a-f]{8}\.pdf\z/)
          pdf = PDF::Reader.new(path)
          pdf_text = pdf.pages.map(&:text).join(' ')
          expect(pdf_text).to include('TCNH41526398') # first doc : docx
          expect(pdf_text).to include('journée de montage') # second doc: pdf
        end
        subject
      end
    end

    context 'on two field', skip: 'waiting for Office suite' do
      let(:controle) { FactoryBot.build :copy_file_field, :with_multiple_fields }
      it 'store pdf', vcr: { cassette_name: 'copy_file_field-2' } do
        expect(SetAnnotationValue).to receive(:set_piece_justificative_on_annotation) do |_dossier, _instructeur, _annotation, path, filename|
          expect(filename).to match(/-[0-9a-f]{8}\.pdf\z/)
          pdf = PDF::Reader.new(path)
          pdf_text = pdf.pages.map(&:text).join(' ')
          expect(pdf_text).to include('TCNH41526398') # first doc : docx
          expect(pdf_text).to include('journée de montage') # second doc: pdf
          expect(pdf_text).to include('Eucalyptus') # third doc: pdf
        end
        subject
      end
    end
  end

  context 'early-exit (rien à copier)' do
    let(:source_file) { double('SourceFile', checksum: 'abc123', filename: 'doc.pdf', url: 'http://example/doc.pdf') }
    let(:source_champ) { double('PieceJustificativeChamp', __typename: 'PieceJustificativeChamp', files: [source_file], label: 'PV') }
    let(:target_annotation_files) { [double('TargetFile', checksum: 'abc123', filename: 'PV existant.pdf')] }
    let(:target_annotation) { double('PieceJustificativeChamp', __typename: 'PieceJustificativeChamp', files: target_annotation_files, label: 'PV Final') }
    let(:fake_dossier) { double('Dossier', number: dossier_nb, state: 'en_construction', champs: [source_champ], annotations: [target_annotation]) }

    before do
      allow(demarche).to receive(:instructeur).and_return(instructeur)
      allow(controle).to receive(:instructeur_id_for).and_return(1)
    end

    context 'mode individuel (convert_to_pdf: false)' do
      let(:controle) { FactoryBot.build :copy_file_field, convert_to_pdf: false }

      it 'ne télécharge rien quand toutes les sources sont déjà sur la cible' do
        expect(PieceJustificativeCache).not_to receive(:get)
        expect(SetAnnotationValue).not_to receive(:set_piece_justificative_on_annotation)
        controle.process(demarche, fake_dossier)
        expect(controle.dossier_updated?).to be_falsey
      end
    end

    context 'mode combiné (convert_to_pdf: true)' do
      let(:controle) { FactoryBot.build :copy_file_field }
      let(:signature) { Digest::SHA1.hexdigest('abc123')[0..7] }
      let(:target_annotation_files) { [double('TargetFile', checksum: 'autre', filename: "PV Final 2026-01-01 09h00-#{signature}.pdf")] }

      it 'ne convertit pas quand la signature des sources est déjà présente dans le nom' do
        expect(PieceJustificativeCache).not_to receive(:get)
        expect(SetAnnotationValue).not_to receive(:set_piece_justificative_on_annotation)
        controle.process(demarche, fake_dossier)
        expect(controle.dossier_updated?).to be_falsey
      end
    end
  end
end
