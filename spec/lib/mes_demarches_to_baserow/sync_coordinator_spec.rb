# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MesDemarchesToBaserow::SyncCoordinator do
  describe '#sync_dossier — étape avis' do
    let(:main_table_id) { 100 }
    let(:baserow_config) { { 'table_id' => main_table_id } }
    let(:options) { {} }

    let(:main_table) { instance_double(Baserow::Table, table_id: main_table_id) }
    let(:upserter) { instance_double(MesDemarchesToBaserow::RowUpserter, upsert_row: 42) }
    let(:client) { instance_double(Baserow::Client) }
    let(:field_filter) { instance_double(MesDemarchesToBaserow::FieldFilter) }
    let(:avis_syncer) { instance_double(MesDemarchesToBaserow::AvisSyncer) }
    let(:dossier) do
      double('Dossier', number: 12_345, champs: [], annotations: [], demandeur: nil, usager: nil,
                        labels: nil, date_depot: nil, date_passage_en_instruction: nil,
                        date_traitement: nil, state: 'en_instruction')
    end

    before do
      allow(Baserow::Config).to receive(:table).with(main_table_id, anything).and_return(main_table)
      allow(Baserow::Config).to receive(:client).and_return(client)
      allow(client).to receive(:list_fields).and_return([])
      allow(MesDemarchesToBaserow::FieldFilter).to receive(:new).and_return(field_filter)
      allow(field_filter).to receive(:filter_syncable_fields) { |data| data }
      allow(main_table).to receive(:find_by_normalized).and_return([])
      allow(MesDemarchesToBaserow::RowUpserter).to receive(:new).and_return(upserter)
      allow(MesDemarchesToBaserow::AvisSyncer).to receive(:new).and_return(avis_syncer)
      allow(avis_syncer).to receive(:sync)

      structure_client = instance_double(Baserow::StructureClient)
      allow(Baserow::StructureClient).to receive(:new).and_return(structure_client)
      allow(structure_client).to receive(:get_table).and_return({ 'database_id' => 1 })
      allow(structure_client).to receive(:list_tables).and_return([])
    end

    it 'appelle AvisSyncer#sync avec le dossier et main_row_id' do
      coordinator = described_class.new(main_table_id, baserow_config, options)
      coordinator.sync_dossier(dossier)

      expect(avis_syncer).to have_received(:sync).with(dossier, 42, kind_of(Proc))
    end
  end
end
