# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe MesDemarchesToBaserow::AvisTableBuilder do
  let(:main_table_id) { 100 }
  let(:application_id) { 1 }
  let(:workspace_id) { 1 }
  let(:structure_client) { instance_double(Baserow::StructureClient) }

  let(:builder) do
    described_class.new(main_table_id, application_id, workspace_id, structure_client: structure_client)
  end

  before do
    allow(structure_client).to receive(:get_table).with(main_table_id).and_return({ 'id' => 100 })
    allow(structure_client).to receive(:field_exists?).with(main_table_id, 'Dossier').and_return(true)
  end

  describe '#preview' do
    context 'quand la table Avis n\'existe pas' do
      before do
        allow(structure_client).to receive(:list_applications).with(workspace_id)
                                                              .and_return([{ 'id' => application_id, 'tables' => [] }])
      end

      it 'indique que la table sera créée avec toutes les colonnes manquantes' do
        result = builder.preview
        expect(result[:will_create_table]).to be true
        expect(result[:missing_fields]).to include('Avis', 'Dossier', 'Question', 'Réponse', 'Pièces jointes')
      end
    end

    context 'quand la table Avis existe avec quelques colonnes' do
      before do
        allow(structure_client).to receive(:list_applications).with(workspace_id)
                                                              .and_return([{ 'id' => application_id,
                                                                             'tables' => [{ 'id' => 200, 'name' => 'Avis' }] }])
        allow(structure_client).to receive(:get_table_fields).with(200)
                                                             .and_return([
                                                                           { 'name' => 'Avis', 'type' => 'text', 'primary' => true },
                                                                           { 'name' => 'Dossier', 'type' => 'link_row' },
                                                                           { 'name' => 'Question', 'type' => 'long_text' }
                                                                         ])
      end

      it 'liste les colonnes manquantes' do
        result = builder.preview
        expect(result[:will_create_table]).to be false
        expect(result[:existing_fields]).to include('Avis', 'Dossier', 'Question')
        expect(result[:missing_fields]).to include('Réponse', 'Pièces jointes')
        expect(result[:missing_fields]).not_to include('Question')
      end
    end
  end

  describe '#build!' do
    context 'quand la table Avis n\'existe pas' do
      before do
        allow(structure_client).to receive(:list_applications).with(workspace_id)
                                                              .and_return([{ 'id' => application_id, 'tables' => [] }])
        allow(structure_client).to receive(:create_table)
          .and_return({ 'id' => 200, 'name' => 'Avis' })
        allow(structure_client).to receive(:get_table_fields).with(200).and_return([
                                                                                     { 'name' => 'Name', 'type' => 'text', 'primary' => true, 'id' => 999 }
                                                                                   ])
        allow(structure_client).to receive(:update_field).and_return({})
        allow(structure_client).to receive(:create_field).and_return({})
        allow(structure_client).to receive(:get_field_by_name).and_return(nil)
      end

      it 'crée la table puis toutes les colonnes standard' do
        result = builder.build!

        expect(result[:table_created]).to be true
        expect(result[:fields_created]).to include('Dossier', 'Question', 'Réponse', 'Pièces jointes')
        expect(structure_client).to have_received(:create_table).once
      end
    end

    context 'quand la table Avis existe avec structure partielle' do
      before do
        allow(structure_client).to receive(:list_applications).with(workspace_id)
                                                              .and_return([{ 'id' => application_id,
                                                                             'tables' => [{ 'id' => 200, 'name' => 'Avis' }] }])
        allow(structure_client).to receive(:get_table_fields).with(200)
                                                             .and_return([
                                                                           { 'name' => 'Avis', 'type' => 'text', 'primary' => true },
                                                                           { 'name' => 'Question', 'type' => 'long_text' }
                                                                         ])
        allow(structure_client).to receive(:get_field_by_name).with(200, 'Dossier').and_return(nil)
        allow(structure_client).to receive(:create_field).and_return({})
      end

      it 'crée uniquement les colonnes manquantes (ne touche pas Question)' do
        result = builder.build!

        expect(result[:table_created]).to be false
        expect(result[:fields_created]).not_to include('Question')
        expect(result[:fields_created]).to include('Dossier', 'Réponse', 'Pièces jointes')
      end
    end

    context 'quand le link_row Dossier existe mais avec multiple_relationships=true' do
      before do
        allow(structure_client).to receive(:list_applications).with(workspace_id)
                                                              .and_return([{ 'id' => application_id,
                                                                             'tables' => [{ 'id' => 200, 'name' => 'Avis' }] }])
        allow(structure_client).to receive(:get_table_fields).with(200)
                                                             .and_return([{ 'name' => 'Avis', 'type' => 'text', 'primary' => true }])
        allow(structure_client).to receive(:get_field_by_name).with(200, 'Dossier')
                                                              .and_return({ 'id' => 50, 'type' => 'link_row',
                                                                            'link_row_multiple_relationships' => true })
        allow(structure_client).to receive(:update_field).and_return({})
        allow(structure_client).to receive(:create_field).and_return({})
      end

      it 'corrige la configuration vers single relationship' do
        builder.build!
        expect(structure_client).to have_received(:update_field).with(50, hash_including(link_row_multiple_relationships: false))
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
