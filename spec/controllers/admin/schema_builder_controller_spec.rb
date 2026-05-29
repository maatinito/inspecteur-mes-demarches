# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe Admin::SchemaBuilderController, type: :controller do
  let(:user) { create(:user) }
  let(:demarche) { create(:demarche) }

  before { sign_in user }

  describe 'GET #show' do
    it 'rend la page (200)' do
      get :show, params: { demarche_demarche_id: demarche.id }
      expect(response).to have_http_status(:ok)
    end

    it 'assigne @demarche' do
      get :show, params: { demarche_demarche_id: demarche.id }
      expect(controller.instance_variable_get(:@demarche)).to eq(demarche)
    end

    it 'assigne @schema_targets (vide initialement)' do
      get :show, params: { demarche_demarche_id: demarche.id }
      expect(controller.instance_variable_get(:@schema_targets)).to eq([])
    end

    it "404 si la démarche n'existe pas" do
      expect { get :show, params: { demarche_demarche_id: 99_999 } }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'POST #create_target' do
    context 'avec un target_type valide' do
      it 'crée une SchemaTarget' do
        expect do
          post :create_target, params: { demarche_demarche_id: demarche.id, target_type: 'baserow' }, format: :turbo_stream
        end.to change(SchemaTarget, :count).by(1)
      end

      it "rend le turbo_stream remplaçant 'schema-targets'" do
        post :create_target, params: { demarche_demarche_id: demarche.id, target_type: 'baserow' }, format: :turbo_stream
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('schema-targets')
      end

      it 'redirige en HTML' do
        post :create_target, params: { demarche_demarche_id: demarche.id, target_type: 'grist' }
        expect(response).to redirect_to(admin_demarche_schema_path(demarche_demarche_id: demarche.id))
      end
    end

    context 'avec un target_type déjà existant (doublon)' do
      before { create(:schema_target, demarche: demarche, target_type: 'baserow') }

      it 'renvoie 422' do
        post :create_target, params: { demarche_demarche_id: demarche.id, target_type: 'baserow' }, format: :turbo_stream
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'ne crée pas de doublon' do
        expect do
          post :create_target, params: { demarche_demarche_id: demarche.id, target_type: 'baserow' }, format: :turbo_stream
        end.not_to change(SchemaTarget, :count)
      end
    end
  end

  describe 'DELETE #destroy_target' do
    before { create(:schema_target, demarche: demarche, target_type: 'baserow') }

    it 'supprime la SchemaTarget' do
      expect do
        delete :destroy_target, params: { demarche_demarche_id: demarche.id, target_type: 'baserow' }, format: :turbo_stream
      end.to change(SchemaTarget, :count).by(-1)
    end

    it 'rend le turbo_stream' do
      delete :destroy_target, params: { demarche_demarche_id: demarche.id, target_type: 'baserow' }, format: :turbo_stream
      expect(response).to have_http_status(:ok)
    end

    it "renvoie 404 si la target n'existe pas" do
      expect do
        delete :destroy_target, params: { demarche_demarche_id: demarche.id, target_type: 'grist' }, format: :turbo_stream
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'PATCH #update_target_selection' do
    let!(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow', workspace_external_id: nil, application_external_id: nil, main_table_external_id: nil) }

    it 'met à jour les ids externes' do
      patch :update_target_selection, params: {
        demarche_demarche_id: demarche.id,
        target_type: 'baserow',
        workspace_external_id: '10',
        application_external_id: '20',
        main_table_external_id: '30'
      }
      expect(response).to have_http_status(:ok)
      target.reload
      expect(target.workspace_external_id).to eq('10')
      expect(target.application_external_id).to eq('20')
      expect(target.main_table_external_id).to eq('30')
    end
  end

  describe 'GET #list_workspaces' do
    let(:adapter) { instance_double(SchemaBuilders::BaserowTarget, list_workspaces: [{ 'id' => 1, 'name' => 'Workspace A' }]) }

    before do
      allow_any_instance_of(described_class).to receive(:target_adapter).and_return(adapter)
    end

    it 'rend la liste des workspaces en JSON' do
      get :list_workspaces, params: { demarche_demarche_id: demarche.id, target_type: 'baserow' }, format: :json
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to eq([{ 'id' => 1, 'name' => 'Workspace A' }])
    end
  end

  describe 'GET #list_applications' do
    let(:adapter) { instance_double(SchemaBuilders::BaserowTarget) }

    before do
      allow(adapter).to receive(:list_applications).with('42').and_return([{ 'id' => 99, 'name' => 'App X' }])
      allow_any_instance_of(described_class).to receive(:target_adapter).and_return(adapter)
    end

    it 'rend la liste des applications en JSON' do
      get :list_applications, params: { demarche_demarche_id: demarche.id, target_type: 'baserow', workspace_id: '42' }, format: :json
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to eq([{ 'id' => 99, 'name' => 'App X' }])
    end
  end

  describe 'GET #list_tables' do
    let(:adapter) { instance_double(SchemaBuilders::BaserowTarget) }

    before do
      allow(adapter).to receive(:list_tables).with('77').and_return([{ 'id' => 5, 'name' => 'Table Y' }])
      allow_any_instance_of(described_class).to receive(:target_adapter).and_return(adapter)
    end

    it 'rend la liste des tables en JSON' do
      get :list_tables, params: { demarche_demarche_id: demarche.id, target_type: 'baserow', application_id: '77' }, format: :json
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to eq([{ 'id' => 5, 'name' => 'Table Y' }])
    end
  end
end
# rubocop:enable Metrics/BlockLength
