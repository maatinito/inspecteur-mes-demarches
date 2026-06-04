# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::SchemaBuilderLegacyController, type: :controller do
  render_views

  let(:user) { create(:user, :admin) }

  before { sign_in user }

  describe 'GET #index' do
    it 'rend la page (200)' do
      get :index
      expect(response).to have_http_status(:ok)
    end

    it 'expose TOUTES les démarches (admin = sysadmin technique)' do
      demarche_a = create(:demarche, libelle: 'Démarche A')
      demarche_b = create(:demarche, libelle: 'Démarche B')

      get :index

      demarches = controller.instance_variable_get(:@demarches)
      expect(demarches).to include(demarche_a, demarche_b)
    end

    it 'liste les démarches dans la vue avec un lien vers le dashboard' do
      demarche = create(:demarche, libelle: 'Ma démarche')
      get :index
      expect(response.body).to include('Ma démarche')
      expect(response.body).to include(admin_demarche_schema_path(demarche_demarche_id: demarche.id))
    end

    it 'redirige vers la page de login si non authentifié' do
      sign_out user
      get :index
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'redirige un user NON admin vers root (require_admin!)' do
      non_admin = create(:user)
      sign_in non_admin
      get :index
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/administrateur/i)
    end
  end
end
