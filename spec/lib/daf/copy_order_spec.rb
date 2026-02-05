# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe Daf::CopyOrder do
  describe 'configuration validation' do
    context 'with old syntax' do
      it 'accepts champ_destination' do
        expect do
          FactoryBot.build(:copy_order)
        end.not_to raise_error
      end
    end

    context 'with new syntax' do
      it 'accepts champs_destination' do
        expect do
          FactoryBot.build(:copy_order, :with_multiple_fields)
        end.not_to raise_error
      end
    end

    context 'without champ_destination or champs_destination' do
      it 'raises an error' do
        expect do
          FactoryBot.build(:copy_order, champ_destination: nil, valeur: nil)
        end.to raise_error(/Configuration invalide/)
      end
    end
  end

  describe '#fields_configuration' do
    context 'with old syntax' do
      let(:controle) { FactoryBot.build(:copy_order, champ_destination: 'Target', valeur: '{Source}') }

      it 'converts to hash format' do
        config = controle.send(:fields_configuration)
        expect(config).to eq({ 'Target' => '{Source}' })
      end

      it 'handles nil valeur' do
        controle.params[:valeur] = nil
        config = controle.send(:fields_configuration)
        expect(config).to eq({ 'Target' => nil })
      end
    end

    context 'with new syntax' do
      let(:controle) do
        FactoryBot.build(:copy_order, :with_multiple_fields)
      end

      it 'returns the hash as is' do
        config = controle.send(:fields_configuration)
        expected = {
          'Champ texte 1' => '{Source 1}',
          'Champ texte 2' => 'Source directe'
        }
        expect(config).to eq(expected)
      end
    end
  end

  describe '#process_text_value' do
    let(:controle) { FactoryBot.build(:copy_order) }
    let(:row) do
      double('Row',
             champs: [
               double('Champ', label: 'Nom', value: 'Test', __typename: 'TextChamp'),
               double('Champ', label: 'Prenom', value: 'User', __typename: 'TextChamp')
             ])
    end

    before do
      # Mock champ_value pour retourner la valeur directement
      allow(controle).to receive(:champ_value) do |champ|
        champ.respond_to?(:value) ? champ.value : champ
      end
    end

    context 'with template syntax' do
      it 'processes mustache template' do
        allow(controle).to receive(:instanciate).with('{Nom}', row).and_return('Test')
        result = controle.send(:process_text_value, row, '{Nom}')
        expect(result).to eq('Test')
      end
    end

    context 'with direct field reference' do
      it 'extracts field value' do
        allow(controle).to receive(:object_field_values).with(row, 'Nom', log_empty: false).and_return([double(value: 'Test')])
        allow(controle).to receive(:champs_to_values).and_return(['Test'])

        result = controle.send(:process_text_value, row, 'Nom')
        expect(result).to eq('Test')
      end
    end

    context 'with nil config' do
      it 'joins all champ values' do
        allow(controle).to receive(:champs_to_values).with(row.champs).and_return(%w[Test User])

        result = controle.send(:process_text_value, row, nil)
        expect(result).to eq('Test, User')
      end
    end
  end

  describe '#detect_field_type' do
    let(:controle) { FactoryBot.build(:copy_order) }
    let(:text_champ) { double('TextChamp', label: 'Nom', __typename: 'TextChamp') }
    let(:file_champ) { double('FileChamp', label: 'Document', __typename: 'PieceJustificativeChamp') }
    let(:row) { double('Row', champs: [text_champ, file_champ]) }

    context 'with direct field reference to text field' do
      it 'returns :text' do
        result = controle.send(:detect_field_type, row, 'Nom')
        expect(result).to eq(:text)
      end
    end

    context 'with direct field reference to file field' do
      it 'returns :file' do
        result = controle.send(:detect_field_type, row, 'Document')
        expect(result).to eq(:file)
      end
    end

    context 'with template syntax' do
      it 'assumes :text' do
        result = controle.send(:detect_field_type, row, '{Nom}')
        expect(result).to eq(:text)
      end
    end

    context 'with nil config' do
      it 'assumes :text' do
        result = controle.send(:detect_field_type, row, nil)
        expect(result).to eq(:text)
      end
    end

    context 'with unknown field name' do
      it 'assumes :text' do
        result = controle.send(:detect_field_type, row, 'Unknown')
        expect(result).to eq(:text)
      end
    end
  end

  describe '#image_file?' do
    let(:controle) { FactoryBot.build(:copy_order) }

    Daf::CopyOrder::IMAGE_EXTENSIONS.each do |ext|
      it "returns true for #{ext} files" do
        expect(controle.send(:image_file?, "file#{ext}")).to be true
      end

      it "returns true for #{ext.upcase} files (case insensitive)" do
        expect(controle.send(:image_file?, "file#{ext.upcase}")).to be true
      end
    end

    it 'returns false for PDF files' do
      expect(controle.send(:image_file?, 'file.pdf')).to be false
    end

    it 'returns false for DOCX files' do
      expect(controle.send(:image_file?, 'file.docx')).to be false
    end

    it 'returns false for XLSX files' do
      expect(controle.send(:image_file?, 'file.xlsx')).to be false
    end
  end

  describe '#image_file_by_name?' do
    let(:controle) { FactoryBot.build(:copy_order) }

    Daf::CopyOrder::IMAGE_EXTENSIONS.each do |ext|
      it "returns true for #{ext} files" do
        expect(controle.send(:image_file_by_name?, "file#{ext}")).to be true
      end

      it "returns true for #{ext.upcase} files (case insensitive)" do
        expect(controle.send(:image_file_by_name?, "file#{ext.upcase}")).to be true
      end
    end

    it 'returns false for PDF files' do
      expect(controle.send(:image_file_by_name?, 'file.pdf')).to be false
    end

    it 'returns false for DOCX files' do
      expect(controle.send(:image_file_by_name?, 'file.docx')).to be false
    end
  end

  describe '#convert_file_to_pdf' do
    let(:controle) { FactoryBot.build(:copy_order) }

    context 'with PDF file' do
      it 'returns file path as-is' do
        result = controle.send(:convert_file_to_pdf, '/tmp/document.pdf')
        expect(result).to eq('/tmp/document.pdf')
      end
    end

    context 'without OFFICE_PATH' do
      before do
        allow(ENV).to receive(:[]).with('OFFICE_PATH').and_return(nil)
      end

      it 'logs error and returns nil' do
        expect(Rails.logger).to receive(:error).with(/OFFICE_PATH non défini/)
        result = controle.send(:convert_file_to_pdf, '/tmp/document.docx')
        expect(result).to be_nil
      end
    end
  end

  describe '#upload_file_if_needed' do
    let(:controle) { FactoryBot.build(:copy_order) }
    let(:source_file) { double('SourceFile', filename: 'test_file.jpg', checksum: 'abc123') }
    let(:annotation) { double('Annotation', label: 'Documents', files: existing_files) }

    before do
      controle.instance_variable_set(:@dossier, double('Dossier'))
      controle.instance_variable_set(:@demarche, double('Demarche', instructeur: 'instructeur'))
    end

    context 'with image file when already exists (same checksum) - IDEMPOTENCE' do
      let(:existing_files) { [double('File', checksum: 'abc123')] }

      it 'does not download or upload the file again' do
        expect(PieceJustificativeCache).not_to receive(:get)
        expect(SetAnnotationValue).not_to receive(:set_piece_justificative_on_annotation)
        expect(Rails.logger).to receive(:info).with(/déjà présent/)

        result = controle.send(:upload_file_if_needed, annotation, source_file)
        expect(result).to be false
      end
    end

    context 'with image file when does not exist yet' do
      let(:existing_files) { [double('File', checksum: 'different123')] }
      let(:local_path) { '/tmp/downloaded_image.jpg' }

      it 'downloads and uploads the file' do
        expect(PieceJustificativeCache).to receive(:get).with(source_file).and_return(local_path)
        expect(SetAnnotationValue).to receive(:set_piece_justificative_on_annotation)
        expect(Rails.logger).to receive(:info).with(/uploadé avec succès/)

        result = controle.send(:upload_file_if_needed, annotation, source_file)
        expect(result).to be true
      end
    end

    context 'with non-image file (conversion needed)' do
      let(:source_file) { double('SourceFile', filename: 'document.docx', checksum: 'docx123') }
      let(:existing_files) { [] }
      let(:local_path) { '/tmp/document.docx' }
      let(:converted_path) { '/tmp/document.pdf' }
      let(:converted_checksum) { 'pdf456' }

      before do
        controle.instance_variable_set(:@params, { convert_to_pdf: true })
        allow(PieceJustificativeCache).to receive(:get).with(source_file).and_return(local_path)
        allow(controle).to receive(:convert_file_to_pdf).with(local_path).and_return(converted_path)
        allow(FileUpload).to receive(:checksum).with(converted_path).and_return(converted_checksum)
      end

      it 'downloads, converts and uploads the file' do
        expect(SetAnnotationValue).to receive(:set_piece_justificative_on_annotation)
        expect(Rails.logger).to receive(:info).with(/converti et uploadé/)

        result = controle.send(:upload_file_if_needed, annotation, source_file)
        expect(result).to be true
      end

      context 'when converted PDF already exists' do
        let(:existing_files) { [double('File', checksum: 'pdf456', filename: 'document-docx123.pdf')] }

        it 'does not upload again' do
          expect(SetAnnotationValue).not_to receive(:set_piece_justificative_on_annotation)
          expect(Rails.logger).to receive(:info).with(/déjà converti/)

          result = controle.send(:upload_file_if_needed, annotation, source_file)
          expect(result).to be false
        end
      end
    end

    context 'when annotation has no files' do
      let(:existing_files) { nil }
      let(:local_path) { '/tmp/image.jpg' }

      it 'uploads the file' do
        expect(PieceJustificativeCache).to receive(:get).with(source_file).and_return(local_path)
        expect(SetAnnotationValue).to receive(:set_piece_justificative_on_annotation)
        expect(Rails.logger).to receive(:info).with(/uploadé avec succès/)

        result = controle.send(:upload_file_if_needed, annotation, source_file)
        expect(result).to be true
      end
    end

    context 'when upload fails' do
      let(:existing_files) { [] }

      it 'logs error and returns false' do
        allow(PieceJustificativeCache).to receive(:get).and_raise(StandardError, 'Download failed')
        expect(Rails.logger).to receive(:error).with(/Erreur lors du traitement/)

        result = controle.send(:upload_file_if_needed, annotation, source_file)
        expect(result).to be false
      end
    end
  end

  describe 'constants' do
    it 'defines IMAGE_EXTENSIONS' do
      expect(Daf::CopyOrder::IMAGE_EXTENSIONS).to include('.jpg', '.jpeg', '.png', '.gif', '.tiff', '.tif', '.svg')
    end

    it 'defines OUTPUT_DIR' do
      expect(Daf::CopyOrder::OUTPUT_DIR).to eq('tmp/copy_order')
    end
  end
end
# rubocop:enable Metrics/BlockLength
