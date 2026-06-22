# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Grist::FileUploader do
  let(:client) { instance_double(Grist::Client) }
  let(:doc_id) { 'aBC123xYz' }
  let(:uploader) { described_class.new(client, doc_id) }
  let(:url) { 'https://s3.example.test/blob?sig=x' }
  let(:visible_name) { 'FEP DE S CMD 0424.xlsx' }

  let(:download_response) do
    instance_double(Typhoeus::Response, success?: true, code: 200, body: 'contenu-binaire')
  end

  before { allow(Typhoeus).to receive(:get).and_return(download_response) }

  describe '#download_and_upload' do
    it 'uploads the file to Grist under its visible name (not the tempfile name)' do
      captured_basename = nil
      captured_content = nil
      allow(client).to receive(:upload_attachment) do |_doc, path, _name|
        captured_basename = File.basename(path)
        captured_content = File.binread(path)
        [42]
      end

      result = uploader.download_and_upload(url, visible_name)

      expect(result).to eq(42)
      expect(captured_basename).to eq(visible_name)
      expect(captured_content).to eq('contenu-binaire')
    end

    it 'sanitises path separators in the visible name' do
      captured_path = nil
      allow(client).to receive(:upload_attachment) do |_doc, path, _name|
        captured_path = path
        [7]
      end

      uploader.download_and_upload(url, 'dossier/2024 liste.xlsx')

      expect(File.basename(captured_path)).to eq('dossier_2024 liste.xlsx')
    end

    it 'cleans up the temporary file afterwards' do
      captured_path = nil
      allow(client).to receive(:upload_attachment) do |_doc, path, _name|
        captured_path = path
        [1]
      end

      uploader.download_and_upload(url, visible_name)

      expect(File.exist?(captured_path)).to be(false)
    end

    it 'returns nil when the download fails' do
      allow(Typhoeus).to receive(:get).and_return(
        instance_double(Typhoeus::Response, success?: false, code: 404, body: '')
      )
      expect(client).not_to receive(:upload_attachment)

      expect(uploader.download_and_upload(url, visible_name)).to be_nil
    end
  end
end
