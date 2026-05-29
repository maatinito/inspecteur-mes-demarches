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

    it 'sans target, affiche les boutons "+ Ajouter Baserow" et "+ Ajouter Grist"' do
      get "/admin/demarches/#{demarche.id}/schema"
      expect(response.body).to include('+ Ajouter Baserow')
      expect(response.body).to include('+ Ajouter Grist')
    end
  end

  describe 'POST /admin/demarches/:demarche_id/schema/targets' do
    it 'avec un baserow déjà créé, affiche uniquement le bouton "+ Ajouter Grist"' do
      create(:schema_target, demarche: demarche, target_type: 'baserow')
      get "/admin/demarches/#{demarche.id}/schema"
      expect(response.body).not_to include('+ Ajouter Baserow')
      expect(response.body).to include('+ Ajouter Grist')
    end

    it 'crée un baserow target en POST et redirige (HTML)' do
      post "/admin/demarches/#{demarche.id}/schema/targets", params: { target_type: 'baserow' }
      expect(response).to redirect_to("/admin/demarches/#{demarche.id}/schema")
      follow_redirect!
      expect(response.body).to include('Baserow')
      expect(response.body).to include('+ Ajouter Grist')
    end
  end
end
