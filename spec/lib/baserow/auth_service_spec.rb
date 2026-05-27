# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Baserow::AuthService do
  before { described_class.clear_cache }

  describe '.jwt_token' do
    it 'returns a JWT token on successful authentication' do
      # Mock environment variables
      allow(ENV).to receive(:fetch).with('BASEROW_URL', anything).and_return('https://test.baserow.io')
      allow(ENV).to receive(:fetch).with('BASEROW_MASTER_EMAIL').and_return('test@example.com')
      allow(ENV).to receive(:fetch).with('BASEROW_MASTER_PASSWORD').and_return('password123')

      # Mock successful response
      response = double('response', code: 200, body: { 'access_token' => 'jwt-token-123' }.to_json)
      request_mock = double('request', run: response)
      allow(Typhoeus::Request).to receive(:new).and_return(request_mock)

      token = described_class.jwt_token

      expect(token).to eq('jwt-token-123')
    end

    it 'raises AuthError when credentials are invalid' do
      allow(ENV).to receive(:fetch).with('BASEROW_URL', anything).and_return('https://test.baserow.io')
      allow(ENV).to receive(:fetch).with('BASEROW_MASTER_EMAIL').and_return('wrong@example.com')
      allow(ENV).to receive(:fetch).with('BASEROW_MASTER_PASSWORD').and_return('wrongpassword')

      response = double('response', code: 401, body: { 'error' => 'Invalid credentials' }.to_json)
      request_mock = double('request', run: response)
      allow(Typhoeus::Request).to receive(:new).and_return(request_mock)

      expect { described_class.jwt_token }.to raise_error(Baserow::AuthService::AuthError, /Authentification refusée/)
    end

    it 'raises AuthError when environment variables are missing' do
      allow(ENV).to receive(:fetch).with('BASEROW_URL', anything).and_return('https://test.baserow.io')
      key_error = KeyError.new('key not found: "BASEROW_MASTER_EMAIL"')
      allow(key_error).to receive(:key).and_return('BASEROW_MASTER_EMAIL')
      allow(ENV).to receive(:fetch).with('BASEROW_MASTER_EMAIL').and_raise(key_error)

      expect { described_class.jwt_token }.to raise_error(Baserow::AuthService::AuthError, /Variable d'environnement manquante/)
    end
  end

  describe 'cache JWT' do
    let(:response) { double('response', code: 200, body: { 'access_token' => 'jwt-cached' }.to_json) }
    let(:request_mock) { double('request', run: response) }

    before do
      allow(ENV).to receive(:fetch).with('BASEROW_URL', anything).and_return('https://test.baserow.io')
      allow(ENV).to receive(:fetch).with('BASEROW_MASTER_EMAIL').and_return('test@example.com')
      allow(ENV).to receive(:fetch).with('BASEROW_MASTER_PASSWORD').and_return('password123')
      allow(Typhoeus::Request).to receive(:new).and_return(request_mock)
    end

    it 'ne fait qu\'un seul login HTTP pour des appels consécutifs' do
      3.times { described_class.jwt_token }
      expect(Typhoeus::Request).to have_received(:new).once
    end

    it 'refait un login après clear_cache' do
      described_class.jwt_token
      described_class.clear_cache
      described_class.jwt_token
      expect(Typhoeus::Request).to have_received(:new).twice
    end

    it 'refait un login après expiration du TTL' do
      described_class.jwt_token
      now = Time.now.to_i
      allow(Time).to receive(:now).and_return(Time.at(now + Baserow::AuthService::CACHE_TTL + 1))
      described_class.jwt_token
      expect(Typhoeus::Request).to have_received(:new).twice
    end
  end
end
