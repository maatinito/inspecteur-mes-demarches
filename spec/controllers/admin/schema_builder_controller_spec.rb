# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe Admin::SchemaBuilderController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers

  render_views

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

    it 'accepte une mise à jour partielle (juste le workspace)' do
      patch :update_target_selection, params: {
        demarche_demarche_id: demarche.id,
        target_type: 'baserow',
        workspace_external_id: '99'
      }
      expect(response).to have_http_status(:ok)
      expect(target.reload.workspace_external_id).to eq('99')
    end

    it "renvoie 404 si la target n'existe pas" do
      expect do
        patch :update_target_selection, params: {
          demarche_demarche_id: demarche.id,
          target_type: 'grist',
          workspace_external_id: '1'
        }
      end.to raise_error(ActiveRecord::RecordNotFound)
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

  describe 'POST #preview_main_table' do
    let!(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow', application_external_id: '17', main_table_external_id: '101') }
    let(:differ_double) do
      instance_double(SchemaBuilders::Differ, main_table_diff: {
                        to_add: [{ id: 'a', label: 'Nom', type: 'text' }],
                        to_modify: [], ok: [], excluded: []
                      })
    end

    before do
      allow_any_instance_of(described_class).to receive(:demarche_descriptor).and_return(double(:descriptor))
      allow_any_instance_of(described_class).to receive(:target_adapter_for).and_return(double(:adapter))
      allow(SchemaBuilders::Differ).to receive(:new).and_return(differ_double)
    end

    it 'rend un Turbo Stream remplaçant la frame main-table' do
      get :preview_main_table, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("main-table-#{target.id}")
    end

    it 'délègue le calcul au Differ et lui passe la target' do
      expect(SchemaBuilders::Differ).to receive(:new).with(hash_including(target: target)).and_return(differ_double)
      get :preview_main_table, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
    end

    it "404 si la target n'existe pas" do
      expect do
        get :preview_main_table, params: { demarche_demarche_id: demarche.id, target: 'grist' }, format: :turbo_stream
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'POST #build_main_table' do
    let!(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow', application_external_id: '17', main_table_external_id: nil) }
    let(:build_result) { { table_id: 99, table_name: 'Dossiers', action: :created, fields: [] } }
    let(:builder_double) { instance_double(SchemaBuilders::MainTableBuilder, build!: build_result) }

    before do
      allow_any_instance_of(described_class).to receive(:demarche_descriptor).and_return(double(:descriptor))
      allow_any_instance_of(described_class).to receive(:main_table_builder_for).and_return(builder_double)
    end

    it 'met à jour main_table_external_id et last_synced_at' do
      freeze_time = Time.zone.parse('2026-05-28 12:00')
      travel_to(freeze_time) do
        post :build_main_table, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
        target.reload
        expect(target.main_table_external_id).to eq('99')
        expect(target.last_synced_at).to be_within(1.second).of(freeze_time)
      end
    end

    it 'retourne un Turbo Stream avec "créée" quand action: :created' do
      post :build_main_table, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('créée')
    end

    it 'retourne un Turbo Stream avec "mise à jour" quand action: :updated' do
      allow(builder_double).to receive(:build!).and_return(build_result.merge(action: :updated))
      post :build_main_table, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
      expect(response.body).to include('mise à jour')
    end

    it "404 si la target n'existe pas" do
      expect do
        post :build_main_table, params: { demarche_demarche_id: demarche.id, target: 'grist' }, format: :turbo_stream
      end.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'passe excluded_field_ids de la target au builder' do
      target.update!(excluded_field_ids: %w[champ_a champ_b])
      expect(builder_double).to receive(:build!).with(
        anything,
        hash_including(excluded_field_ids: %w[champ_a champ_b])
      ).and_return(build_result)
      post :build_main_table, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
    end
  end

  describe 'POST #preview_avis' do
    let!(:target_baserow) { create(:schema_target, demarche: demarche, target_type: 'baserow', application_external_id: '17', main_table_external_id: '101') }
    let(:preview_result) do
      {
        table_name: 'Avis',
        application_id: '17',
        main_table_id: '101',
        fields: [{ name: 'Dossier', type: 'link_row' }, { name: 'Question', type: 'long_text' }]
      }
    end
    let(:builder_double) { instance_double(SchemaBuilders::AvisBuilder, preview: preview_result) }

    before do
      allow_any_instance_of(described_class).to receive(:avis_builder_for).and_return(builder_double)
    end

    it 'renvoie un Turbo Stream avec le preview' do
      get :preview_avis, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Dossier')
    end

    it 'refuse pour target_type grist' do
      create(:schema_target, demarche: demarche, target_type: 'grist', application_external_id: '17', main_table_external_id: '101')
      get :preview_avis, params: { demarche_demarche_id: demarche.id, target: 'grist' }, format: :turbo_stream
      expect(response).to have_http_status(:bad_request)
    end

    it 'renvoie 412 si la table principale n\'est pas construite' do
      target_baserow.update!(main_table_external_id: nil)
      get :preview_avis, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
      expect(response).to have_http_status(:precondition_failed)
    end
  end

  describe 'POST #build_avis' do
    let!(:target_baserow) { create(:schema_target, demarche: demarche, target_type: 'baserow', application_external_id: '17', main_table_external_id: '101') }
    let(:build_result) { { table_id: 'a99', table_name: 'Avis', action: :created } }
    let(:builder_double) { instance_double(SchemaBuilders::AvisBuilder, build!: build_result) }

    before do
      allow_any_instance_of(described_class).to receive(:avis_builder_for).and_return(builder_double)
    end

    it 'met à jour avis_table_external_id et last_synced_at' do
      post :build_avis, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
      target_baserow.reload
      expect(target_baserow.avis_table_external_id).to eq('a99')
      expect(target_baserow.last_synced_at).to be_present
    end

    it 'retourne un Turbo Stream avec "créée" quand action: :created' do
      post :build_avis, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('créée')
    end

    it 'refuse pour target_type grist' do
      create(:schema_target, demarche: demarche, target_type: 'grist', application_external_id: '17', main_table_external_id: '101')
      post :build_avis, params: { demarche_demarche_id: demarche.id, target: 'grist' }, format: :turbo_stream
      expect(response).to have_http_status(:bad_request)
    end

    it 'renvoie 412 si la table principale n\'est pas construite' do
      target_baserow.update!(main_table_external_id: nil)
      post :build_avis, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
      expect(response).to have_http_status(:precondition_failed)
    end
  end

  describe 'POST #preview_blocks' do
    let!(:target_baserow) { create(:schema_target, demarche: demarche, target_type: 'baserow', application_external_id: '17', main_table_external_id: '101') }
    let(:differ_double) do
      instance_double(SchemaBuilders::Differ, blocks_diff: { blocks_excluded: [], blocks: [] })
    end

    before do
      allow_any_instance_of(described_class).to receive(:demarche_descriptor).and_return(double(:descriptor))
      allow_any_instance_of(described_class).to receive(:target_adapter_for).and_return(double(:adapter))
      allow(SchemaBuilders::Differ).to receive(:new).and_return(differ_double)
    end

    it 'renvoie un Turbo Stream remplaçant la frame blocks' do
      get :preview_blocks, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("blocks-#{target_baserow.id}")
    end

    it 'délègue le calcul au Differ et lui passe la target' do
      expect(SchemaBuilders::Differ).to receive(:new).with(hash_including(target: target_baserow)).and_return(differ_double)
      get :preview_blocks, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
    end

    it 'refuse si main_table_external_id absent' do
      target_baserow.update!(main_table_external_id: nil)
      get :preview_blocks, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
      expect(response).to have_http_status(:precondition_failed)
    end
  end

  describe 'PATCH #toggle_main_table_field_exclusion' do
    let!(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow', application_external_id: '17', main_table_external_id: '101') }
    let(:differ_double) do
      instance_double(SchemaBuilders::Differ, main_table_diff: {
                        to_add: [], to_modify: [], ok: [], excluded: []
                      })
    end

    before do
      allow_any_instance_of(described_class).to receive(:demarche_descriptor).and_return(double(:descriptor))
      allow_any_instance_of(described_class).to receive(:target_adapter_for).and_return(double(:adapter))
      allow(SchemaBuilders::Differ).to receive(:new).and_return(differ_double)
    end

    it 'exclut le champ quand excluded=true' do
      patch :toggle_main_table_field_exclusion,
            params: { demarche_demarche_id: demarche.id, target: 'baserow', field_id: 'champ_xyz', excluded: 'true' },
            format: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(target.reload.excluded_field_ids).to include('champ_xyz')
    end

    it 'réintègre le champ quand excluded=false' do
      target.update!(excluded_field_ids: ['champ_xyz'])
      patch :toggle_main_table_field_exclusion,
            params: { demarche_demarche_id: demarche.id, target: 'baserow', field_id: 'champ_xyz', excluded: 'false' },
            format: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(target.reload.excluded_field_ids).not_to include('champ_xyz')
    end

    it 'renvoie un Turbo Stream remplaçant la frame main-table' do
      patch :toggle_main_table_field_exclusion,
            params: { demarche_demarche_id: demarche.id, target: 'baserow', field_id: 'champ_xyz', excluded: 'true' },
            format: :turbo_stream
      expect(response.body).to include("main-table-#{target.id}")
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    end

    it "404 si la target n'existe pas" do
      expect do
        patch :toggle_main_table_field_exclusion,
              params: { demarche_demarche_id: demarche.id, target: 'grist', field_id: 'champ_xyz', excluded: 'true' },
              format: :turbo_stream
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'PATCH #toggle_block_exclusion' do
    let!(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow', application_external_id: '17', main_table_external_id: '101') }
    let(:differ_double) do
      instance_double(SchemaBuilders::Differ, blocks_diff: { blocks_excluded: [], blocks: [] })
    end

    before do
      allow_any_instance_of(described_class).to receive(:demarche_descriptor).and_return(double(:descriptor))
      allow_any_instance_of(described_class).to receive(:target_adapter_for).and_return(double(:adapter))
      allow(SchemaBuilders::Differ).to receive(:new).and_return(differ_double)
    end

    it 'exclut le bloc quand excluded=true' do
      patch :toggle_block_exclusion,
            params: { demarche_demarche_id: demarche.id, target: 'baserow', block_id: 'b1', excluded: 'true' },
            format: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(target.reload.excluded_block_descriptor_ids).to include('b1')
    end

    it 'réintègre le bloc quand excluded=false' do
      target.update!(excluded_block_descriptor_ids: ['b1'])
      patch :toggle_block_exclusion,
            params: { demarche_demarche_id: demarche.id, target: 'baserow', block_id: 'b1', excluded: 'false' },
            format: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(target.reload.excluded_block_descriptor_ids).not_to include('b1')
    end

    it 'renvoie un Turbo Stream remplaçant la frame blocks' do
      patch :toggle_block_exclusion,
            params: { demarche_demarche_id: demarche.id, target: 'baserow', block_id: 'b1', excluded: 'true' },
            format: :turbo_stream
      expect(response.body).to include("blocks-#{target.id}")
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    end

    it "404 si la target n'existe pas" do
      expect do
        patch :toggle_block_exclusion,
              params: { demarche_demarche_id: demarche.id, target: 'grist', block_id: 'b1', excluded: 'true' },
              format: :turbo_stream
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'PATCH #toggle_block_field_exclusion' do
    let!(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow', application_external_id: '17', main_table_external_id: '101') }
    let!(:block_target) { create(:schema_block_target, schema_target: target, block_descriptor_id: 'b1') }
    let(:differ_double) do
      instance_double(SchemaBuilders::Differ, blocks_diff: { blocks_excluded: [], blocks: [] })
    end

    before do
      allow_any_instance_of(described_class).to receive(:demarche_descriptor).and_return(double(:descriptor))
      allow_any_instance_of(described_class).to receive(:target_adapter_for).and_return(double(:adapter))
      allow(SchemaBuilders::Differ).to receive(:new).and_return(differ_double)
    end

    it 'exclut le champ dans le bloc quand excluded=true' do
      patch :toggle_block_field_exclusion,
            params: { demarche_demarche_id: demarche.id, target: 'baserow', block_id: 'b1', field_id: 'champ_xyz', excluded: 'true' },
            format: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(block_target.reload.excluded_field_ids).to include('champ_xyz')
    end

    it 'réintègre le champ dans le bloc quand excluded=false' do
      block_target.update!(excluded_field_ids: ['champ_xyz'])
      patch :toggle_block_field_exclusion,
            params: { demarche_demarche_id: demarche.id, target: 'baserow', block_id: 'b1', field_id: 'champ_xyz', excluded: 'false' },
            format: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(block_target.reload.excluded_field_ids).not_to include('champ_xyz')
    end

    it 'renvoie un Turbo Stream remplaçant la frame blocks' do
      patch :toggle_block_field_exclusion,
            params: { demarche_demarche_id: demarche.id, target: 'baserow', block_id: 'b1', field_id: 'champ_xyz', excluded: 'true' },
            format: :turbo_stream
      expect(response.body).to include("blocks-#{target.id}")
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    end

    it "404 si la target n'existe pas" do
      expect do
        patch :toggle_block_field_exclusion,
              params: { demarche_demarche_id: demarche.id, target: 'grist', block_id: 'b1', field_id: 'champ_xyz', excluded: 'true' },
              format: :turbo_stream
      end.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "404 si le bloc n'existe pas" do
      expect do
        patch :toggle_block_field_exclusion,
              params: { demarche_demarche_id: demarche.id, target: 'baserow', block_id: 'inexistant', field_id: 'champ_xyz', excluded: 'true' },
              format: :turbo_stream
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'POST #build_blocks' do
    let!(:target_baserow) { create(:schema_target, demarche: demarche, target_type: 'baserow', application_external_id: '17', main_table_external_id: '101') }
    let(:builder_double) do
      instance_double(SchemaBuilders::BlockBuilder, build!: [
                        { block_descriptor_id: 'b1', table_name: 'Membres', table_id: 'bt1', action: :created },
                        { block_descriptor_id: 'b2', table_name: 'Activités', table_id: 'bt2', action: :updated }
                      ])
    end

    before do
      allow_any_instance_of(described_class).to receive(:demarche_descriptor).and_return(double(:descriptor))
      allow_any_instance_of(described_class).to receive(:block_builder_for).and_return(builder_double)
    end

    it 'crée des SchemaBlockTarget pour chaque résultat' do
      expect do
        post :build_blocks, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
      end.to change { target_baserow.schema_block_targets.count }.by(2)
    end

    it 'idempotent (réexécution ne duplique pas les SchemaBlockTarget)' do
      post :build_blocks, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
      expect do
        post :build_blocks, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
      end.not_to(change { target_baserow.schema_block_targets.count })
    end

    it 'retourne un Turbo Stream avec le résumé' do
      post :build_blocks, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
      expect(response.body).to include('Membres').and include('created')
    end

    it 'refuse si main_table_external_id absent' do
      target_baserow.update!(main_table_external_id: nil)
      post :build_blocks, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
      expect(response).to have_http_status(:precondition_failed)
    end

    it 'passe excluded_block_ids et excluded_fields_per_block au builder' do
      target_baserow.update!(excluded_block_descriptor_ids: ['b3'])
      create(:schema_block_target, schema_target: target_baserow, block_descriptor_id: 'b1', excluded_field_ids: ['champ_a'])
      expect(builder_double).to receive(:build!).with(
        anything,
        hash_including(
          excluded_block_ids: ['b3'],
          excluded_fields_per_block: hash_including('b1' => ['champ_a'])
        )
      ).and_return([])
      post :build_blocks, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
    end
  end
end
# rubocop:enable Metrics/BlockLength
