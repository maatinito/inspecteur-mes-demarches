# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe Admin::SchemaBuilderController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers

  render_views

  let(:user) { create(:user, :admin) }
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
    let(:builder_double) { instance_double(SchemaBuilders::MainTableBuilder, build!: build_result, resolve_table_id: nil) }

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

    it 'accepte une cible Grist et lit ses champs au format Grist' do
      create(:schema_target, demarche: demarche, target_type: 'grist', application_external_id: 'doc1', main_table_external_id: 'Dossiers')
      allow(builder_double).to receive(:preview).and_return(
        preview_result.merge(fields: [{ id: 'Question', fields: { label: 'Question', type: 'Text' } }])
      )
      get :preview_avis, params: { demarche_demarche_id: demarche.id, target: 'grist' }, format: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Question')
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

    it 'construit la table Avis pour une cible Grist' do
      grist = create(:schema_target, demarche: demarche, target_type: 'grist', application_external_id: 'doc1', main_table_external_id: 'Dossiers')
      allow(builder_double).to receive(:build!).and_return(table_id: 'Avis', table_name: 'Avis', action: :created)
      post :build_avis, params: { demarche_demarche_id: demarche.id, target: 'grist' }, format: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(grist.reload.avis_table_external_id).to eq('Avis')
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

    it "refuse d'exclure Email usager en DLNUF (422)" do
      target.update!(referentiel: 'dlnuf')
      patch :toggle_main_table_field_exclusion,
            params: { demarche_demarche_id: demarche.id, target: 'baserow', field_id: 'metadata:email_usager', excluded: 'true' },
            format: :turbo_stream
      expect(response).to have_http_status(:unprocessable_entity)
      expect(target.reload.excluded_field_ids).to be_empty
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
      allow_any_instance_of(described_class).to receive(:referentiel_dlnuf)
        .and_return(instance_double(SchemaBuilders::ReferentielDlnuf, type_lu: :archive))
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

  describe 'type de référentiel (archive ou DLNUF)' do
    let(:dlnuf_service) { instance_double(SchemaBuilders::ReferentielDlnuf, colonnes_fichier: []) }
    let(:resolu) { '101' }
    let(:builder_double) { instance_double(SchemaBuilders::MainTableBuilder, resolve_table_id: resolu) }
    let(:created) { { table_id: 99, table_name: 'Dossiers', action: :created, fields: [] } }

    before do
      allow_any_instance_of(described_class).to receive(:demarche_descriptor).and_return(double(:descriptor))
      allow_any_instance_of(described_class).to receive(:main_table_builder_for).and_return(builder_double)
      allow_any_instance_of(described_class).to receive(:referentiel_dlnuf).and_return(dlnuf_service)
    end

    def construire(table = 'baserow')
      post :build_main_table, params: { demarche_demarche_id: demarche.id, target: table }, format: :turbo_stream
    end

    context 'table neuve en DLNUF' do
      let(:resolu) { nil }
      let!(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow', application_external_id: '17', main_table_external_id: nil, referentiel: 'dlnuf') }

      it 'appelle finaliser! avec creee: true' do
        allow(builder_double).to receive(:build!).and_return(created)
        expect(dlnuf_service).to receive(:finaliser!).with(99, creee: true).and_return(9115)
        construire
        expect(response.body).to include('créée')
      end

      it 'affiche le refus de finaliser! en alert-danger, sans erreur 500' do
        allow(builder_double).to receive(:build!).and_return(created)
        allow(dlnuf_service).to receive(:finaliser!).and_raise(Referentiel::Verrou::Refus, 'colonne Email usager absente')
        construire
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('alert-danger').and include('colonne Email usager absente')
      end
    end

    context 'table supprimée côté Baserow (archive)' do
      let(:resolu) { nil }
      let!(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow', application_external_id: '17', main_table_external_id: '101') }

      it 'ne vérifie rien et laisse build! recréer la table' do
        expect(dlnuf_service).not_to receive(:type_lu)
        expect(builder_double).to receive(:build!).and_return(created)
        construire
        expect(target.reload.main_table_external_id).to eq('99')
      end
    end

    context 'table existante' do
      let!(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow', application_external_id: '17', main_table_external_id: '101', referentiel: 'dlnuf') }

      it 'DLNUF pointée sur une table sans marqueur : aucune écriture' do
        allow(dlnuf_service).to receive(:type_lu).with('101').and_return(:archive)
        expect(builder_double).not_to receive(:build!)
        construire
        expect(response.body).to include('créer une nouvelle table')
      end

      it 'archive pointée sur une table marquée DLNUF : aucune écriture' do
        target.update!(referentiel: 'archive')
        allow(dlnuf_service).to receive(:type_lu).with('101').and_return(:dlnuf)
        expect(builder_double).not_to receive(:build!)
        construire
        expect(response.body).to include('créer une nouvelle table')
      end

      it 'marqueur illisible : aucune écriture' do
        allow(dlnuf_service).to receive(:type_lu).and_return(:invalid)
        expect(builder_double).not_to receive(:build!)
        construire
        expect(response.body).to include('Marqueur illisible')
      end

      it 'DLNUF avec colonne fichier : aucune écriture' do
        allow(dlnuf_service).to receive_messages(type_lu: :dlnuf, colonnes_fichier: %w[RIB Photo])
        expect(builder_double).not_to receive(:build!)
        construire
        expect(response.body).to include('Colonne(s) fichier interdite(s) dans une table DLNUF : RIB, Photo.')
      end

      it 'vérifie la table retrouvée par nom quand aucun id n\'est sélectionné' do
        target.update!(main_table_external_id: nil)
        allow(dlnuf_service).to receive(:type_lu).with('101').and_return(:archive)
        expect(builder_double).not_to receive(:build!)
        construire
        expect(response.body).to include('créer une nouvelle table')
        expect(target.reload.main_table_external_id).to be_nil
        expect(target.last_synced_at).to be_nil
      end

      it 'affiche une erreur API de lecture sans erreur 500' do
        allow(dlnuf_service).to receive(:type_lu).and_raise(Baserow::APIError.new({ 'error' => 'HTTP 500' }, 500))
        expect(builder_double).not_to receive(:build!)
        construire
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('alert-danger').and include('Lecture de la table 101 impossible')
      end

      it 'build_blocks applique les mêmes refus' do
        allow(dlnuf_service).to receive(:type_lu).and_return(:archive)
        expect_any_instance_of(described_class).not_to receive(:block_builder_for)
        post :build_blocks, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
        expect(response.body).to include('créer une nouvelle table')
      end

      context 'build_blocks en DLNUF : tables de bloc réutilisées' do
        let(:blocs) do
          instance_double(SchemaBuilders::BlockBuilder,
                          preview: [{ table_name: 'Membres' }], existing_table_id: 862, build!: [])
        end

        before do
          target = demarche.schema_targets.find_by!(target_type: 'baserow')
          target.update!(application_external_id: '17')
          allow(dlnuf_service).to receive(:type_lu).and_return(:dlnuf)
          allow(dlnuf_service).to receive(:colonnes_fichier).with('101').and_return([])
          allow_any_instance_of(described_class).to receive(:block_builder_for).and_return(blocs)
        end

        def construire_blocs
          post :build_blocks, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
        end

        it 'refuse une table réutilisée qui n\'est pas liée à cette table DLNUF' do
          allow(dlnuf_service).to receive(:tables_liees).with('17', '101').and_return([])
          expect(blocs).not_to receive(:build!)
          construire_blocs
          expect(response.body).to include('La table de bloc Membres n&#39;appartient pas à cette table DLNUF')
        end

        it 'refuse une table liée qui porte une colonne fichier' do
          allow(dlnuf_service).to receive(:tables_liees).and_return([862])
          allow(dlnuf_service).to receive(:colonnes_fichier).with(862).and_return(['Pièce'])
          expect(blocs).not_to receive(:build!)
          construire_blocs
          expect(response.body).to include('Colonne(s) fichier interdite(s) dans une table DLNUF').and include('Pièce')
        end

        it 'construit quand les tables réutilisées sont liées et sans fichier' do
          allow(dlnuf_service).to receive(:tables_liees).and_return([862])
          allow(dlnuf_service).to receive(:colonnes_fichier).with(862).and_return([])
          expect(blocs).to receive(:build!).and_return([])
          construire_blocs
        end
      end

      it 'build_avis et preview_avis renvoient 412 en DLNUF' do
        post :build_avis, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
        expect(response).to have_http_status(:precondition_failed)
        get :preview_avis, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
        expect(response).to have_http_status(:precondition_failed)
      end
    end

    describe 'PATCH selection du référentiel' do
      let!(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow') }

      it 'enregistre referentiel=dlnuf avant synchronisation' do
        patch :update_target_selection, params: { demarche_demarche_id: demarche.id, target_type: 'baserow', referentiel: 'dlnuf' }
        expect(response).to have_http_status(:ok)
        expect(target.reload).to be_dlnuf
      end

      it 'renvoie 422 après synchronisation' do
        target.update!(last_synced_at: Time.current)
        patch :update_target_selection, params: { demarche_demarche_id: demarche.id, target_type: 'baserow', referentiel: 'dlnuf' }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(target.reload).not_to be_dlnuf
      end
    end

    describe 'POST #retablir_marqueur' do
      let!(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow', main_table_external_id: '101') }

      it 'rétablit le marqueur' do
        expect(dlnuf_service).to receive(:retablir!).with('101')
        post :retablir_marqueur, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
        expect(response.body).to include('Marqueur rétabli')
      end

      it 'affiche le refus en alert-danger' do
        allow(dlnuf_service).to receive(:retablir!).and_raise(Referentiel::Verrou::Refus, 'inconnue de ce robot')
        post :retablir_marqueur, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('alert-danger').and include('inconnue de ce robot')
      end
    end

    describe 'POST #vider_table' do
      let!(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow', main_table_external_id: '101') }
      let(:adapter) { instance_double(SchemaBuilders::BaserowTarget) }

      before do
        allow(dlnuf_service).to receive_messages(application_de: 17, tables_liees: [201, 202])
        allow_any_instance_of(described_class).to receive(:target_adapter_for).and_return(adapter)
        demarche.update!(checked_at: Time.zone.parse('2026-11-01 10:00'))
      end

      def vider
        post :vider_table, params: { demarche_demarche_id: demarche.id, target: 'baserow' }, format: :turbo_stream
      end

      it 'rend 403 sur une table sans marqueur DLNUF, sans rien effacer' do
        allow(dlnuf_service).to receive(:type_lu).with('101').and_return(:archive)
        expect(adapter).not_to receive(:vider_table)
        vider
        expect(response).to have_http_status(:forbidden)
        expect(demarche.reload.checked_at).to eq(Time.zone.parse('2026-11-01 10:00'))
      end

      it 'rend 403 sans table principale' do
        target.update!(main_table_external_id: nil)
        expect(adapter).not_to receive(:vider_table)
        vider
        expect(response).to have_http_status(:forbidden)
      end

      it 'rend 403 pour une cible qui n\'est pas Baserow' do
        create(:schema_target, demarche: demarche, target_type: 'grist', main_table_external_id: 'T1')
        expect(adapter).not_to receive(:vider_table)
        post :vider_table, params: { demarche_demarche_id: demarche.id, target: 'grist' }, format: :turbo_stream
        expect(response).to have_http_status(:forbidden)
      end

      it 'rend 403 quand le marqueur est illisible' do
        allow(dlnuf_service).to receive(:type_lu).with('101').and_return(:invalid)
        expect(adapter).not_to receive(:vider_table)
        vider
        expect(response).to have_http_status(:forbidden)
      end

      it 'affiche l\'erreur de lecture du marqueur sans rien effacer' do
        allow(dlnuf_service).to receive(:type_lu).and_raise(Baserow::APIError.new({ 'error' => 'boom' }, 500))
        expect(adapter).not_to receive(:vider_table)
        vider
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('alert-danger')
        expect(demarche.reload.checked_at).to eq(Time.zone.parse('2026-11-01 10:00'))
      end

      context 'sur une table DLNUF' do
        before do
          allow(dlnuf_service).to receive(:type_lu).with('101').and_return(:dlnuf)
          # Un backend_table_id périmé ou détecté par nom ne doit jamais être effacé.
          create(:schema_block_target, schema_target: target, block_descriptor_id: 'b1', backend_table_id: '999')
        end

        it 'ne vide que les tables liées à la table principale, lues sur Baserow' do
          expect(dlnuf_service).to receive(:tables_liees).with(17, '101').and_return([201])
          expect(adapter).to receive(:vider_table).with(201).ordered.and_return(1)
          expect(adapter).to receive(:vider_table).with('101').ordered.and_return(1)
          expect(adapter).not_to receive(:vider_table).with('999')
          vider
        end

        it 'vide les blocs puis la table principale et remet le curseur à EPOCH' do
          expect(adapter).to receive(:vider_table).with(201).ordered.and_return(2)
          expect(adapter).to receive(:vider_table).with(202).ordered.and_return(0)
          expect(adapter).to receive(:vider_table).with('101').ordered.and_return(5)
          vider
          expect(response).to have_http_status(:ok)
          expect(response.body).to include('7 ligne(s) effacée(s)')
          expect(demarche.reload.checked_at).to eq(DossierActions::EPOCH)
        end

        it 'ne remet pas le curseur si l\'effacement échoue en cours de route' do
          allow(adapter).to receive(:vider_table).with(201).and_return(2)
          allow(adapter).to receive(:vider_table).with(202).and_raise(Baserow::APIError.new({ 'error' => 'boom' }, 500))
          vider
          expect(response.body).to include('alert-danger')
          expect(demarche.reload.checked_at).to eq(Time.zone.parse('2026-11-01 10:00'))
        end
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
