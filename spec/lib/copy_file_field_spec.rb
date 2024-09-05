# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Publipostage do
  let(:dossier_nb) { 441_984 }
  let(:dossier) { DossierActions.on_dossier(dossier_nb) }
  let(:demarche) { double(Demarche) }
  let(:instructeur) { 'instructeur' }
  let(:result_path) { "tmp/copy_file_field/PV #{dossier_nb}.pdf" }

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
      FileUtils.rm_f(result_path)
      allow(controle).to receive(:delete)
      allow(demarche).to receive(:instructeur).and_return(instructeur)
      allow(controle).to receive(:instructeur_id_for).and_return(1)
    end

    context 'on one field', skip: 'waiting for Office suite' do
      let(:controle) { FactoryBot.build :copy_file_field }
      it 'store pdf', vcr: { cassette_name: 'copy_file_field-1' } do
        expect(SetAnnotationValue).to receive(:set_piece_justificative).with(dossier, 1, controle.params[:champ_cible], result_path)
        subject

        pdf = PDF::Reader.new(result_path)
        pdf_text = pdf.pages.map(&:text).join(' ')
        expect(pdf_text).to include('TCNH41526398') # first doc : docx
        expect(pdf_text).to include('journée de montage') # second doc: pdf
      end
    end

    context 'on two field', skip: 'waiting for Office suite' do
      let(:controle) { FactoryBot.build :copy_file_field, :with_multiple_fields }
      it 'store pdf', vcr: { cassette_name: 'copy_file_field-2' } do
        expect(SetAnnotationValue).to receive(:set_piece_justificative).with(dossier, 1, controle.params[:champ_cible], result_path)
        subject

        pdf = PDF::Reader.new(result_path)
        pdf_text = pdf.pages.map(&:text).join(' ')
        expect(pdf_text).to include('TCNH41526398') # first doc : docx
        expect(pdf_text).to include('journée de montage') # second doc: pdf
        expect(pdf_text).to include('Eucalyptus') # third doc: pdf
      end
    end
  end
end
