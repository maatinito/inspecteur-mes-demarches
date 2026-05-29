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

  describe 'section Avis sur le dashboard' do
    context 'avec une cible Baserow et une table principale construite' do
      before { create(:schema_target, demarche: demarche, target_type: 'baserow', main_table_external_id: '101') }

      it 'affiche la section Avis avec boutons Aperçu et Build' do
        get "/admin/demarches/#{demarche.id}/schema"
        expect(response.body).to include('Table Avis')
        expect(response.body).to include('Aperçu')
        expect(response.body).to include('Build')
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
      before { create(:schema_target, demarche: demarche, target_type: 'baserow', main_table_external_id: '101') }

      it 'affiche la section Blocs avec boutons' do
        get "/admin/demarches/#{demarche.id}/schema"
        expect(response.body).to include('Blocs répétables')
        expect(response.body).to include('Aperçu')
      end
    end

    context 'avec une cible Baserow sans main_table' do
      before { create(:schema_target, demarche: demarche, target_type: 'baserow', main_table_external_id: nil) }

      it "affiche un message d'attente sans boutons d'action sur la section Blocs" do
        get "/admin/demarches/#{demarche.id}/schema"
        expect(response.body).to include('table principale doit être créée avant les blocs')
      end
    end
  end
end
