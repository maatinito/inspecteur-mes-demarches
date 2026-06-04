# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin::SchemaBuilderLegacy', type: :request do
  let(:user) { create(:user, :admin) }

  before { sign_in user }

  describe 'GET /admin/schema_builder_legacy' do
    it 'retourne 200 pour un admin' do
      get '/admin/schema_builder_legacy'
      expect(response).to have_http_status(:ok)
    end

    it 'affiche un message explicatif sur la transition' do
      get '/admin/schema_builder_legacy'
      expect(response.body).to include('Schéma de copie')
      expect(response.body).to include('dashboard')
    end

    it 'liste toutes les démarches (admin = sysadmin technique)' do
      demarche = create(:demarche, libelle: 'Démarche A')
      get '/admin/schema_builder_legacy'
      expect(response.body).to include('Démarche A')
      expect(response.body).to include("/admin/demarches/#{demarche.id}/schema")
    end

    it 'redirige vers login si non authentifié' do
      sign_out user
      get '/admin/schema_builder_legacy'
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'redirige un user NON admin vers root (require_admin!)' do
      sign_out user
      non_admin = create(:user)
      sign_in non_admin
      get '/admin/schema_builder_legacy'
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/administrateur/i)
    end
  end
end
