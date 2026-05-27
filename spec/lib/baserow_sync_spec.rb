# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe BaserowSync do
  describe '#process — synchronisation des avis' do
    let(:demarche) { double('Demarche', id: 999) }
    let(:dossier) do
      double('Dossier',
             number: 12_345,
             state: 'en_instruction',
             champs: [],
             annotations: [],
             demandeur: nil,
             usager: nil,
             labels: nil,
             date_depot: nil,
             date_passage_en_instruction: nil,
             date_traitement: nil)
    end

    let(:main_table_id) { 100 }
    let(:avis_table_id) { 200 }

    let(:main_table) { instance_double(Baserow::Table, table_id: main_table_id) }
    let(:avis_table) { instance_double(Baserow::Table, table_id: avis_table_id) }
    let(:upserter) { instance_double(MesDemarchesToBaserow::RowUpserter, upsert_row: 42) }
    let(:structure_client) { instance_double(Baserow::StructureClient) }
    let(:client) { instance_double(Baserow::Client) }
    let(:field_filter) { instance_double(MesDemarchesToBaserow::FieldFilter) }
    let(:file_uploader) { instance_double(Baserow::FileUploader) }

    let(:avis_with_attachment) do
      double('Avis',
             id: 'AV1',
             question: 'Avis service A',
             reponse: 'Favorable',
             question_label: nil,
             question_answer: nil,
             date_question: nil,
             date_reponse: nil,
             expert: nil,
             claimant: nil,
             attachments: [
               double('File', filename: 'avis.pdf', url: 'https://md.gp.pf/avis.pdf', byte_size: 1000)
             ])
    end

    let(:avis_without_attachment) do
      double('Avis',
             id: 'AV2',
             question: 'Avis service B',
             reponse: nil,
             question_label: nil,
             question_answer: nil,
             date_question: nil,
             date_reponse: nil,
             expert: nil,
             claimant: nil,
             attachments: [])
    end

    let(:avis_meta) do
      {
        'Avis' => { 'type' => 'text', 'id' => 1, 'primary' => true },
        'Dossier' => { 'type' => 'link_row', 'id' => 2,
                       'link_row_table_id' => main_table_id,
                       'link_row_table_primary_field' => { 'name' => 'Dossier', 'type' => 'number' } },
        'Question' => { 'type' => 'long_text', 'id' => 3 },
        'Réponse' => { 'type' => 'long_text', 'id' => 4 },
        'Pièces jointes' => { 'type' => 'file', 'id' => 5 }
      }
    end

    before do
      # Tables Baserow
      allow(Baserow::Config).to receive(:table).with(main_table_id, anything).and_return(main_table)
      allow(Baserow::Config).to receive(:table).with(avis_table_id, anything).and_return(avis_table)

      # Client Baserow (champs de la table principale)
      allow(Baserow::Config).to receive(:client).and_return(client)
      allow(client).to receive(:list_fields).and_return([])

      # FieldFilter pour table principale + chargement métadonnées table Avis
      allow(MesDemarchesToBaserow::FieldFilter).to receive(:new).and_return(field_filter)
      allow(field_filter).to receive(:filter_syncable_fields) { |data| data }
      allow(field_filter).to receive(:load_baserow_fields).and_return(avis_meta)

      # Recherche de la row existante (aucune)
      allow(main_table).to receive(:find_by_normalized).and_return([])

      # Upsert table principale → renvoie main_row_id 42
      allow(MesDemarchesToBaserow::RowUpserter).to receive(:new).and_return(upserter)

      # StructureClient pour discover_application_tables et validation Avis
      allow(Baserow::StructureClient).to receive(:new).and_return(structure_client)
      allow(structure_client).to receive(:get_table).with(main_table_id).and_return({ 'database_id' => 1 })
      allow(structure_client).to receive(:list_tables).with(1).and_return([
                                                                            { 'id' => avis_table_id, 'name' => 'Avis' }
                                                                          ])
      allow(structure_client).to receive(:get_table_fields).with(avis_table_id).and_return([
                                                                                             { 'name' => 'Avis', 'type' => 'text', 'primary' => true },
                                                                                             { 'name' => 'Dossier', 'type' => 'link_row',
                                                                                               'link_row_table_id' => main_table_id,
                                                                                               'link_row_multiple_relationships' => false }
                                                                                           ])

      # Pas de rows Avis existantes pour ce dossier
      allow(avis_table).to receive(:find_by_link_row_id).with('Dossier', 42).and_return([])
      allow(avis_table).to receive(:create_row).and_return({ 'id' => 0 })

      # AvisFetcher → 2 avis
      allow(MesDemarches::AvisFetcher).to receive(:fetch).with(12_345)
                                                         .and_return([avis_with_attachment, avis_without_attachment])

      # FileUploader pour la PJ de AV1
      allow(Baserow::FileUploader).to receive(:new).and_return(file_uploader)
      allow(file_uploader).to receive(:download_and_upload)
        .with('https://md.gp.pf/avis.pdf', 'avis.pdf')
        .and_return({ 'name' => 'uploaded_hash_abc', 'visible_name' => 'avis.pdf' })
    end

    it 'crée 2 rows dans la table Avis (1 avec PJ à uploader, 1 sans PJ)' do
      params = { baserow: { 'table_id' => main_table_id }, etat_du_dossier: 'en_instruction' }
      checker = described_class.new(params)
      checker.process(demarche, dossier)

      expect(avis_table).to have_received(:create_row).twice
      expect(avis_table).to have_received(:create_row).with(hash_including('Question' => 'Avis service A'))
      expect(avis_table).to have_received(:create_row).with(hash_including('Question' => 'Avis service B'))
    end
  end
end
# rubocop:enable Metrics/BlockLength
