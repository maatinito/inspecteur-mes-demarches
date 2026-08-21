# frozen_string_literal: true

require 'rails_helper'

# Réponses tronquées et délai de transfert : ce qui se passe quand la table
# devient volumineuse. Fichier séparé de client_spec.rb pour ne pas mêler ces
# cas aux tests de routes.
RSpec.describe Grist::Client do
  let(:client) { described_class.new('https://grist.example.pf', 'cle') }

  describe 'réponse tronquée' do
    # Un transfert coupé garde le code 200 obtenu avant la coupure : le corps est
    # un JSON valide amputé de sa fin. C'est le cas observé sur une table de
    # 19 000 lignes, dont la réponse dépasse 2 Mo.
    let(:tronquee) do
      instance_double(Typhoeus::Response, code: 200,
                                          body: '{"records": [{"id": 1, "fields": {"Nom": "Perm')
    end

    before do
      allow(Typhoeus::Request).to receive(:new).and_return(instance_double(Typhoeus::Request, run: tronquee))
    end

    it 'lève une APIError explicite et non une JSON::ParserError nue' do
      expect { client.list_records('doc', 'Substances') }.to raise_error(Grist::APIError)
    end

    it 'indique le volume reçu et la piste du délai' do
      client.list_records('doc', 'Substances')
      raise 'aucune erreur levée'
    rescue Grist::APIError => e
      expect(e.message).to include("#{tronquee.body.bytesize} octets reçus")
      expect(e.message).to include('GRIST_TIMEOUT')
    end
  end

  describe '#sql' do
    let(:reponse) { instance_double(Typhoeus::Response, code: 200, body: '{"records": []}') }

    it 'interroge la route SQL du document avec la requête et le délai Grist' do
      expect(Typhoeus::Request).to receive(:new) do |url, options|
        expect(url).to start_with('https://grist.example.pf/api/docs/doc/sql?')
        expect(url).to include(CGI.escape('select id from Substances'))
        expect(url).to include('timeout=8000')
        expect(options).to include(method: :get)
        instance_double(Typhoeus::Request, run: reponse)
      end

      client.sql('doc', 'select id from Substances')
    end
  end

  describe 'délai de transfert' do
    let(:reponse) { instance_double(Typhoeus::Response, code: 200, body: '{}') }

    it 'accorde par défaut plus que les 30 s qui coupaient les grosses tables' do
      expect(Typhoeus::Request).to receive(:new)
        .with(anything, hash_including(timeout: 120))
        .and_return(instance_double(Typhoeus::Request, run: reponse))

      client.list_records('doc', 'Substances')
    end

    it 'se laisse surcharger par GRIST_TIMEOUT pour un document volumineux' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('GRIST_TIMEOUT', 120).and_return('300')

      expect(Typhoeus::Request).to receive(:new)
        .with(anything, hash_including(timeout: 300))
        .and_return(instance_double(Typhoeus::Request, run: reponse))

      client.list_records('doc', 'Substances')
    end
  end
end
