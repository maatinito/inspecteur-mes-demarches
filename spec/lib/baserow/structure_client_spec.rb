# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Baserow::StructureClient do
  let(:client) { described_class.new('jwt') }

  # perform_request est le seul point d'accès réseau : on le remplace (VCR intercepte Typhoeus.stub).
  def appels
    @appels ||= []
  end

  def simuler(&reponses)
    allow(client).to receive(:perform_request) do |method, url, options|
      appels << { method: method, url: url, body: options[:body] }
      reponses.call(url)
    end
  end

  def reponse(code, corps = nil)
    Typhoeus::Response.new(code: code, body: corps&.to_json)
  end

  describe '#list_row_ids' do
    it 'parcourt toutes les pages de 200 lignes' do
      simuler do |url|
        if url.end_with?('page=1')
          reponse(200, { 'results' => [{ 'id' => 1 }, { 'id' => 2 }], 'next' => 'suite' })
        else
          reponse(200, { 'results' => [{ 'id' => 3 }], 'next' => nil })
        end
      end

      expect(client.list_row_ids(7)).to eq([1, 2, 3])
    end
  end

  describe '#delete_rows' do
    it 'efface 450 identifiants en trois appels de 200, 200 et 50' do
      simuler { reponse(204) }

      client.delete_rows(7, (1..450).to_a)

      expect(appels.map { |a| JSON.parse(a[:body])['items'].size }).to eq([200, 200, 50])
      expect(appels.map { |a| a[:url] }.uniq).to eq(["#{client.base_url}/api/database/rows/table/7/batch-delete/"])
    end

    it 'ne fait aucun appel pour une liste vide' do
      simuler { reponse(204) }
      client.delete_rows(7, [])
      expect(appels).to be_empty
    end

    it 'lève quand Baserow refuse le lot' do
      simuler { reponse(400, { 'error' => 'ERROR_X' }) }

      expect { client.delete_rows(7, [1]) }.to raise_error(Baserow::APIError)
    end
  end
end
