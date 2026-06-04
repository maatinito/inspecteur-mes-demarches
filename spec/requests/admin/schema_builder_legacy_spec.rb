# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin::SchemaBuilderLegacy', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET /admin/schema_builder_legacy' do
    it 'retourne 200' do
      get '/admin/schema_builder_legacy'
      expect(response).to have_http_status(:ok)
    end

    it 'affiche un message explicatif sur la transition' do
      get '/admin/schema_builder_legacy'
      expect(response.body).to include('Schéma de copie')
      expect(response.body).to include('dashboard')
    end

    it 'liste les démarches dont le user est instructeur, avec un lien vers le dashboard' do
      demarche = create(:demarche, libelle: 'Démarche A')
      user.demarches << demarche
      get '/admin/schema_builder_legacy'
      expect(response.body).to include('Démarche A')
      expect(response.body).to include("/admin/demarches/#{demarche.id}/schema")
    end

    it "ne liste pas les démarches dont le user n'est pas instructeur (scoping sécurité)" do
      create(:demarche, libelle: 'Démarche autre instructeur')
      get '/admin/schema_builder_legacy'
      expect(response.body).not_to include('Démarche autre instructeur')
    end

    it 'redirige vers login si non authentifié' do
      sign_out user
      get '/admin/schema_builder_legacy'
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
