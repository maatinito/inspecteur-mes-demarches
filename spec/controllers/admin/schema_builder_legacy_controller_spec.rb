# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::SchemaBuilderLegacyController, type: :controller do
  render_views

  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET #index' do
    it 'rend la page (200)' do
      get :index
      expect(response).to have_http_status(:ok)
    end

    it 'assigne @demarches (uniquement celles dont le user est instructeur)' do
      demarche = create(:demarche)
      user.demarches << demarche
      get :index
      expect(controller.instance_variable_get(:@demarches)).to include(demarche)
    end

    it "expose les démarches accessibles à l'utilisateur connecté" do
      demarche_user = create(:demarche, libelle: 'Démarche de Bob')
      user.demarches << demarche_user
      _demarche_autre = create(:demarche, libelle: 'Démarche autre')

      get :index

      demarches = controller.instance_variable_get(:@demarches)
      # User a au moins une démarche associée → on ne renvoie QUE celles-ci
      expect(demarches).to contain_exactly(demarche_user)
    end

    it 'liste les démarches dans la vue avec un lien vers le dashboard' do
      demarche = create(:demarche, libelle: 'Ma démarche')
      user.demarches << demarche
      get :index
      expect(response.body).to include('Ma démarche')
      expect(response.body).to include(admin_demarche_schema_path(demarche_demarche_id: demarche.id))
    end

    it 'redirige vers la page de login si non authentifié' do
      sign_out user
      get :index
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
