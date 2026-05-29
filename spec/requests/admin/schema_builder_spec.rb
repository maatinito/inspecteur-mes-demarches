# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin::SchemaBuilder', type: :request do
  let(:user) { create(:user) }
  let(:demarche) { create(:demarche) }

  before { sign_in user }

  describe 'GET /admin/demarches/:demarche_id/schema' do
    it 'rend le dashboard (200)' do
      get "/admin/demarches/#{demarche.id}/schema"
      expect(response).to have_http_status(:ok)
    end

    it 'affiche le titre de la démarche' do
      get "/admin/demarches/#{demarche.id}/schema"
      expect(response.body).to include(demarche.libelle)
    end

    it 'indique aucune cible configurée initialement' do
      get "/admin/demarches/#{demarche.id}/schema"
      expect(response.body).to include('Aucune cible configurée')
    end
  end
end
