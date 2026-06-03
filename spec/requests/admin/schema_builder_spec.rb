# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
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

  describe 'section Avis sur le dashboard' do
    context 'avec une cible Baserow et une table principale construite' do
      let!(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow', application_external_id: '17', main_table_external_id: '101') }

      before do
        adapter = instance_double(SchemaBuilders::BaserowTarget)
        allow(adapter).to receive(:list_tables).with('17').and_return([])
        allow_any_instance_of(Admin::SchemaBuilderController)
          .to receive(:target_adapter_for).and_return(adapter)
      end

      it 'affiche la section Avis en lazy load (Turbo Frame vers preview_avis)' do
        get "/admin/demarches/#{demarche.id}/schema"
        expect(response.body).to include('Table Avis')
        expect(response.body).to include("avis-#{target.id}")
        expect(response.body).to include('/avis/preview')
        expect(response.body).to include('loading="lazy"')
      end
    end

    context 'avec une cible Baserow sans table principale' do
      before { create(:schema_target, demarche: demarche, target_type: 'baserow', main_table_external_id: nil) }

      it 'affiche la section Avis avec message attendant la table principale' do
        get "/admin/demarches/#{demarche.id}/schema"
        expect(response.body).to include('Table Avis')
        expect(response.body).to include('table principale doit être créée')
      end
    end

    context 'avec une cible Grist' do
      before { create(:schema_target, demarche: demarche, target_type: 'grist') }

      it 'affiche la section Avis avec message indisponible (pas de boutons)' do
        get "/admin/demarches/#{demarche.id}/schema"
        expect(response.body).to include('Table Avis')
        expect(response.body).to include('indisponible pour Grist')
      end
    end
  end

  describe 'section Blocs sur le dashboard' do
    context 'avec une cible Baserow et main_table créée' do
      let!(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow', main_table_external_id: '101') }

      it 'affiche la section Blocs avec un Turbo Frame lazy' do
        get "/admin/demarches/#{demarche.id}/schema"
        expect(response.body).to include("blocks-#{target.id}")
        expect(response.body).to include('loading="lazy"')
        expect(response.body).to include('/blocks/preview')
      end
    end

    context 'avec une cible Baserow sans main_table' do
      before { create(:schema_target, demarche: demarche, target_type: 'baserow', main_table_external_id: nil) }

      it "affiche un message d'attente sur la section Blocs" do
        get "/admin/demarches/#{demarche.id}/schema"
        expect(response.body).to include('Blocs répétables')
      end
    end
  end

  describe 'section Table principale sur le dashboard (mode lazy)' do
    let!(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow') }

    it 'rend un Turbo Frame lazy avec src vers preview_main_table' do
      get "/admin/demarches/#{demarche.id}/schema"
      expect(response.body).to include("main-table-#{target.id}")
      expect(response.body).to include('loading="lazy"')
      expect(response.body).to include('/main_table/preview')
    end

    it 'rend le skeleton "Chargement de l\'aperçu" pour la table principale' do
      get "/admin/demarches/#{demarche.id}/schema"
      expect(response.body).to include('Chargement')
    end
  end

  describe 'flow end-to-end : diff -> exclusion -> build' do
    # Stub minimal d'un champ_descriptor MD utilisé par le Differ.
    test_descriptor = Struct.new(:id, :label, :__typename, :options) do
      def champ_descriptors
        []
      end
    end

    # Stub minimal d'un demarche_descriptor MD (réponse GraphQL simplifiée).
    test_demarche_descriptor = Struct.new(:champ_descriptors)

    let!(:target) do
      create(:schema_target,
             demarche: demarche,
             target_type: 'baserow',
             application_external_id: '17',
             main_table_external_id: '101')
    end

    let(:champ_a) { test_descriptor.new(id: 'c_a_id', label: 'Adresse', __typename: 'TextChampDescriptor') }
    let(:champ_b) { test_descriptor.new(id: 'c_b_id', label: 'Montant', __typename: 'IntegerNumberChampDescriptor') }
    let(:champ_c) { test_descriptor.new(id: 'c_c_id', label: 'Email', __typename: 'EmailChampDescriptor') }

    let(:demarche_descriptor) do
      test_demarche_descriptor.new([champ_a, champ_b, champ_c])
    end

    let(:adapter) { instance_double(SchemaBuilders::BaserowTarget) }

    before do
      # Côté cible : seule "Adresse" existe déjà -> ok ; "Montant" et "Email"
      # sont à ajouter.
      allow(adapter).to receive(:get_table_fields).with('101').and_return([
                                                                            { 'name' => 'Adresse', 'type' => 'text' }
                                                                          ])
      # list_tables est appelé par autodetect_avis_table dans show — défaut vide.
      allow(adapter).to receive(:list_tables).with('17').and_return([])
      allow_any_instance_of(Admin::SchemaBuilderController)
        .to receive(:demarche_descriptor).and_return(demarche_descriptor)
      allow_any_instance_of(Admin::SchemaBuilderController)
        .to receive(:target_adapter_for).and_return(adapter)
    end

    it 'GET /schema rend le Turbo Frame lazy avec src vers preview' do
      get "/admin/demarches/#{demarche.id}/schema"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("main-table-#{target.id}")
      expect(response.body).to include('loading="lazy"')
      expect(response.body).to include('/main_table/preview')
    end

    it 'GET preview_main_table affiche les 4 zones du diff' do
      get "/admin/demarches/#{demarche.id}/schema/targets/baserow/main_table/preview"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('À ajouter (2)')
      expect(response.body).to include('Montant')
      expect(response.body).to include('Email')
      expect(response.body).to include('1 champs conformes')
    end

    it 'PATCH toggle exclusion bascule un champ dans Ignorés et rafraîchit le diff' do
      patch "/admin/demarches/#{demarche.id}/schema/targets/baserow/main_table/fields/c_b_id/exclusion",
            params: { excluded: 'true' },
            headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include("main-table-#{target.id}")
      expect(target.reload.excluded_field_ids).to include('c_b_id')
      expect(response.body).to include('Ignorés (1)')
      expect(response.body).to include('Montant')
      expect(response.body).to include('À ajouter (1)')
    end

    it 'GET preview après exclusion fait apparaître Montant dans Ignorés' do
      target.update!(excluded_field_ids: ['c_b_id'])

      get "/admin/demarches/#{demarche.id}/schema/targets/baserow/main_table/preview"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Ignorés (1)')
      expect(response.body).to include('Montant')
      # Le compteur "À ajouter" tombe à 1 (seul Email reste à ajouter)
      expect(response.body).to include('À ajouter (1)')
    end

    it 'POST build_main_table passe excluded_field_ids au MainTableBuilder' do
      target.update!(excluded_field_ids: ['c_b_id'])

      build_result = { table_id: 99, table_name: 'Dossiers démarche', action: :updated, fields: [] }
      builder_double = instance_double(SchemaBuilders::MainTableBuilder)
      allow_any_instance_of(Admin::SchemaBuilderController)
        .to receive(:main_table_builder_for).and_return(builder_double)
      expect(builder_double).to receive(:build!).with(
        anything,
        hash_including(excluded_field_ids: ['c_b_id'])
      ).and_return(build_result)

      post "/admin/demarches/#{demarche.id}/schema/targets/baserow/main_table/build",
           headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:ok)
    end
  end
end
# rubocop:enable Metrics/BlockLength
