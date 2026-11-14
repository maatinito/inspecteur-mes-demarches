# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MesDemarchesToBaserow::SyncCoordinator do # rubocop:disable Metrics/BlockLength
  include ActiveSupport::Testing::TimeHelpers

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
                        date_traitement: nil, groupe_instructeur: nil, state: 'en_instruction',
                        instructeurs: [], traitements: [])
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

      # FileUploader appelle TokenManager.get_token → ENV['BASEROW_API_TOKEN'].
      # On stubbe la construction pour éviter la dépendance à l'env en CI.
      file_uploader = instance_double(Baserow::FileUploader, download_and_upload: nil)
      allow(Baserow::FileUploader).to receive(:new).and_return(file_uploader)

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

  describe 'type de table (archive ou DLNUF)' do # rubocop:disable Metrics/BlockLength
    let(:main_table_id) { 100 }
    let(:baserow_config) { { 'table_id' => main_table_id } }
    let(:main_table) { instance_double(Baserow::Table, table_id: main_table_id) }
    let(:upserter) { instance_double(MesDemarchesToBaserow::RowUpserter, upsert_row: 42) }
    let(:client) { instance_double(Baserow::Client) }
    let(:field_filter) { instance_double(MesDemarchesToBaserow::FieldFilter) }
    let(:avis_syncer) { instance_double(MesDemarchesToBaserow::AvisSyncer, sync: nil) }
    let(:dossier) do
      double('Dossier', number: 12_345, champs: [], annotations: [], demandeur: nil, usager: nil,
                        labels: nil, date_depot: nil, date_passage_en_instruction: nil,
                        date_traitement: nil, groupe_instructeur: nil, state: 'en_instruction',
                        instructeurs: [], traitements: [])
    end
    let(:description_dlnuf) { Referentiel::Marqueur.description_table(mode: :dlnuf, proprietaire: 11) }
    let(:champs_dlnuf) do
      [
        { 'id' => 10, 'name' => 'Dossier', 'type' => 'text', 'primary' => true, 'description' => description_dlnuf },
        { 'id' => 11, 'name' => 'Email', 'type' => 'text', 'primary' => false, 'description' => nil }
      ]
    end
    let(:champs) { champs_dlnuf }
    let(:structure_client) { instance_double(Baserow::StructureClient) }

    before do
      allow(Baserow::Config).to receive(:table).with(main_table_id, anything).and_return(main_table)
      allow(Baserow::Config).to receive(:client).and_return(client)
      allow(client).to receive(:list_fields).with(main_table_id).and_return(champs)
      allow(main_table).to receive(:list_rows).and_return({ 'count' => 0, 'results' => [] })
      allow(MesDemarchesToBaserow::FieldFilter).to receive(:new).and_return(field_filter)
      allow(field_filter).to receive(:filter_syncable_fields) { |data| data }
      allow(main_table).to receive(:find_by_normalized).and_return([])
      allow(MesDemarchesToBaserow::RowUpserter).to receive(:new).and_return(upserter)
      allow(MesDemarchesToBaserow::AvisSyncer).to receive(:new).and_return(avis_syncer)
      allow(Baserow::FileUploader).to receive(:new)
        .and_return(instance_double(Baserow::FileUploader, download_and_upload: nil))

      allow(Baserow::StructureClient).to receive(:new).and_return(structure_client)
      allow(structure_client).to receive(:get_table).and_return({ 'database_id' => 1 })
      allow(structure_client).to receive(:list_tables).and_return([])
    end

    around do |example|
      adaptateur = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      example.run
    ensure
      ActiveJob::Base.queue_adapter = adaptateur
    end

    def enregistrer(mode, proprietaire = nil)
      ReferentielTable.create!(backend: 'baserow', table_ref: main_table_id.to_s, mode:, proprietaire:)
    end

    context 'sans marqueur' do
      let(:champs) do
        [{ 'id' => 10, 'name' => 'Dossier', 'type' => 'text', 'primary' => true, 'description' => nil }]
      end

      it 'reste en archive sans marqueur et synchronise comme avant' do
        coordinator = described_class.new(main_table_id, baserow_config, {})
        coordinator.sync_dossier(dossier)

        expect(coordinator.mode).to eq(:archive)
        expect(avis_syncer).to have_received(:sync).with(dossier, 42, kind_of(Proc))
      end
    end

    it 'passe en DLNUF quand le marqueur et l\'enregistrement concordent' do
      enregistrer('dlnuf', 11)

      coordinator = described_class.new(main_table_id, baserow_config, {})

      expect(coordinator.mode).to eq(:dlnuf)
    end

    it 'adopte en DLNUF une table marquée qu\'il voit pour la première fois' do
      coordinator = described_class.new(main_table_id, baserow_config, {})

      expect(coordinator.mode).to eq(:dlnuf)
      expect(ReferentielTable.find_by(backend: 'baserow', table_ref: '100'))
        .to have_attributes(mode: 'dlnuf', proprietaire: 11)
    end

    it 'refuse une table DLNUF dont le marqueur a été retiré' do
      enregistrer('dlnuf', 11)
      champs[0]['description'] = nil

      expect { described_class.new(main_table_id, baserow_config, {}) }
        .to raise_error(Referentiel::Verrou::Refus)
    end

    it 'refuse une table DLNUF contenant une colonne fichier' do
      champs << { 'id' => 12, 'name' => 'RIB', 'type' => 'file', 'primary' => false, 'description' => nil }

      expect { described_class.new(main_table_id, baserow_config, {}) }
        .to raise_error(Referentiel::Verrou::Refus, /colonne fichier RIB/) { |e|
          expect(e.table).to eq(ReferentielTable.find_by(backend: 'baserow', table_ref: '100'))
        }
    end

    it 'refuse une table DLNUF dont le propriétaire ne désigne aucune colonne' do
      champs.pop

      expect { described_class.new(main_table_id, baserow_config, {}) }
        .to raise_error(Referentiel::Verrou::Refus, /propriétaire/)
    end

    context 'avec une table de bloc liée' do
      let(:colonnes_bloc) do
        {
          'Dossier' => { 'id' => 1, 'type' => 'link_row', 'readonly' => false,
                         'config' => { 'link_row_table_id' => main_table_id } },
          'Piece' => { 'id' => 2, 'type' => 'file', 'config' => {}, 'readonly' => false }
        }
      end

      before do
        allow(structure_client).to receive(:list_tables)
          .and_return([{ 'name' => 'Principale', 'id' => main_table_id }, { 'name' => 'Bloc', 'id' => 200 }])
        allow(field_filter).to receive(:load_baserow_fields).and_return(colonnes_bloc)
      end

      it 'refuse à l\'initialisation une table de bloc DLNUF contenant une colonne fichier' do
        expect { described_class.new(main_table_id, baserow_config, {}) }
          .to raise_error(Referentiel::Verrou::Refus, /colonne fichier Piece/)
      end

      it 'n alerte qu une fois pour une colonne fichier dans une table de bloc' do
        enregistrer('dlnuf', 11)
        expect { signaler_deux_passes }.to have_enqueued_mail(NotificationMailer, :report_error).once
        expect(ReferentielTable.last.refus_depuis).to be_present
      end

      it 'ignore une table de l\'application non liée à la table principale' do
        colonnes_bloc['Dossier']['config']['link_row_table_id'] = 999

        expect(described_class.new(main_table_id, baserow_config, {}).mode).to eq(:dlnuf)
      end
    end

    def signaler_deux_passes
      allow(Sentry).to receive(:capture_message)
      2.times do
        described_class.new(main_table_id, baserow_config, {})
      rescue Referentiel::Verrou::Refus => e
        Referentiel::Alerte.signaler(e)
      end
    end

    it 'n alerte qu une fois, sans toucher la date de refus, pour une colonne fichier en DLNUF' do
      enregistrer('dlnuf', 11)
      champs << { 'id' => 12, 'name' => 'RIB', 'type' => 'file', 'primary' => false, 'description' => nil }

      expect { signaler_deux_passes }.to have_enqueued_mail(NotificationMailer, :report_error).once
      premier = ReferentielTable.last.refus_depuis
      expect(premier).to be_present

      travel 1.hour do
        expect { signaler_deux_passes }.not_to have_enqueued_mail(NotificationMailer, :report_error)
      end
      expect(ReferentielTable.last.refus_depuis).to eq(premier)
    end

    it 'ne lit ni les tables de l\'application ni les lignes en archive' do
      champs[0]['description'] = nil
      expect(Baserow::StructureClient).not_to receive(:new)

      expect(described_class.new(main_table_id, baserow_config, {}).mode).to eq(:archive)
      expect(main_table).not_to have_received(:list_rows)
    end

    it 'ne synchronise pas les avis en DLNUF' do
      coordinator = described_class.new(main_table_id, baserow_config, {})
      coordinator.sync_dossier(dossier)

      expect(MesDemarchesToBaserow::AvisSyncer).not_to have_received(:new)
    end
  end
end
