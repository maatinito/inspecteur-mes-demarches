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

    context 'avec un mapping' do
      def descripteur(stable_id, label)
        double(id: Base64.urlsafe_encode64("Champ-#{stable_id}"), label:)
      end

      let(:revision) do
        double(champ_descriptors: [descripteur(140_066, 'NOM Président(e)')],
               annotation_descriptors: [descripteur(160_000, 'Montant accordé')])
      end

      before do
        resultat = double(data: double(demarche: double(draft_revision: revision, published_revision: nil)))
        allow(MesDemarches).to receive(:query).and_return(resultat)
        allow(Rails.logger).to receive(:warn)
      end

      it 'journalise les avertissements du Mapping une seule fois par passe' do
        coordinator = described_class.new(main_table_id, baserow_config, options,
                                          mapping: { 'Inconnue' => 140_066 }, gabarit: ->(texte) { texte })
        2.times { coordinator.sync_dossier(dossier) }

        expect(Rails.logger).to have_received(:warn).with(/BaserowSync mapping: démarche 100.*Inconnue/).once
      end

      it 'ne synchronise aucun bloc répétable' do
        coordinator = described_class.new(main_table_id, baserow_config, options,
                                          mapping: { 'Inconnue' => 140_066 }, gabarit: ->(texte) { texte })
        allow(coordinator).to receive(:sync_repetable_blocks)
        coordinator.sync_dossier(dossier)

        expect(coordinator).not_to have_received(:sync_repetable_blocks)
      end
    end

    it 'sans mapping, ne lit pas la révision de la démarche' do
      allow(MesDemarches).to receive(:query)
      described_class.new(main_table_id, baserow_config, options)

      expect(MesDemarches).not_to have_received(:query)
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

    context 'e-mail du titulaire' do
      let(:usager) { double('User', email: 'Jean.Dupont@Example.PF') }
      let(:dossier_usager) do
        double('Dossier', number: 12_345, champs: [], annotations: [], demandeur: nil, usager:,
                          labels: nil, date_depot: nil, date_passage_en_instruction: nil,
                          date_traitement: nil, groupe_instructeur: nil, state: 'en_instruction',
                          instructeurs: [], traitements: [])
      end

      it 'écrit l\'e-mail en minuscules dans la colonne propriétaire, sans copier de fichier, en DLNUF' do
        enregistrer('dlnuf', 11)
        televerseur = instance_double(Baserow::FileUploader, download_and_upload: nil)
        allow(Baserow::FileUploader).to receive(:new).and_return(televerseur)
        coordinator = described_class.new(main_table_id, baserow_config, {})
        coordinator.sync_dossier(dossier_usager)

        expect(upserter).to have_received(:upsert_row)
          .with(12_345, hash_including('Email' => 'jean.dupont@example.pf'), existing_row: nil)
        expect(televerseur).not_to have_received(:download_and_upload)
      end

      it 'vide la colonne propriétaire quand le dossier n\'a pas d\'usager, en DLNUF' do
        enregistrer('dlnuf', 11)
        coordinator = described_class.new(main_table_id, baserow_config, {})
        coordinator.sync_dossier(dossier)

        expect(upserter).to have_received(:upsert_row)
          .with(12_345, hash_including('Email' => nil), existing_row: nil)
      end

      it 'écrit l\'e-mail tel quel en archive' do
        champs[0]['description'] = nil
        champs << { 'id' => 12, 'name' => 'Email usager', 'type' => 'text', 'primary' => false, 'description' => nil }
        coordinator = described_class.new(main_table_id, baserow_config, {})
        coordinator.sync_dossier(dossier_usager)

        expect(upserter).to have_received(:upsert_row)
          .with(12_345, hash_including('Email usager' => 'Jean.Dupont@Example.PF'), existing_row: nil)
      end
    end

    it 'ne synchronise pas les avis en DLNUF' do
      coordinator = described_class.new(main_table_id, baserow_config, {})
      coordinator.sync_dossier(dossier)

      expect(MesDemarchesToBaserow::AvisSyncer).not_to have_received(:new)
    end

    describe '#delete_dossier' do
      let(:bloc_table) { instance_double(Baserow::Table, table_id: 200) }
      let(:autre_table) { instance_double(Baserow::Table, table_id: 300) }
      let(:colonnes_bloc) do
        { 'Dossier' => { 'id' => 1, 'type' => 'link_row', 'readonly' => false,
                         'config' => { 'link_row_table_id' => main_table_id } } }
      end
      let(:colonnes_autre) do
        { 'Dossier' => { 'id' => 1, 'type' => 'link_row', 'readonly' => false,
                         'config' => { 'link_row_table_id' => 999 } } }
      end

      before do
        allow(structure_client).to receive(:list_tables)
          .and_return([{ 'name' => 'Principale', 'id' => main_table_id }, { 'name' => 'Bloc', 'id' => 200 },
                       { 'name' => 'Autre', 'id' => 300 }])
        allow(Baserow::Config).to receive(:table).with(200, anything).and_return(bloc_table)
        allow(Baserow::Config).to receive(:table).with(300, anything).and_return(autre_table)
        allow(MesDemarchesToBaserow::FieldFilter).to receive(:new).with(200, anything)
                                                                  .and_return(instance_double(MesDemarchesToBaserow::FieldFilter, load_baserow_fields: colonnes_bloc))
        allow(MesDemarchesToBaserow::FieldFilter).to receive(:new).with(300, anything)
                                                                  .and_return(instance_double(MesDemarchesToBaserow::FieldFilter, load_baserow_fields: colonnes_autre))
        allow(main_table).to receive(:find_by_normalized).with('Dossier', '12345').and_return([{ 'id' => 42 }], [])
        allow(main_table).to receive(:delete_row).and_return(true)
        allow(bloc_table).to receive(:find_by_link_row_id).with('Dossier', 42)
                                                          .and_return([{ 'id' => 7 }, { 'id' => 8 }], [])
        allow(bloc_table).to receive(:delete_row).and_return(true)
      end

      it 'efface les lignes des blocs puis la ligne du dossier en DLNUF' do
        enregistrer('dlnuf', 11)
        coordinator = described_class.new(main_table_id, baserow_config, {})

        expect(bloc_table).to receive(:delete_row).with(7).ordered
        expect(bloc_table).to receive(:delete_row).with(8).ordered
        expect(main_table).to receive(:delete_row).with(42).ordered

        expect(coordinator.delete_dossier(12_345)).to be(true)
      end

      it 'ne touche pas une table non liée à la table principale' do
        enregistrer('dlnuf', 11)
        described_class.new(main_table_id, baserow_config, {}).delete_dossier(12_345)

        expect(Baserow::Config).not_to have_received(:table).with(300, anything)
      end

      it 'lève une erreur sans toucher la ligne principale quand l\'effacement d\'une ligne de bloc échoue' do
        enregistrer('dlnuf', 11)
        allow(bloc_table).to receive(:delete_row).with(7).and_return(false)
        coordinator = described_class.new(main_table_id, baserow_config, {})

        expect { coordinator.delete_dossier(12_345) }.to raise_error(/200.*7/)
        expect(main_table).not_to have_received(:delete_row)
      end

      it 'lève une erreur quand l\'effacement de la ligne principale échoue' do
        enregistrer('dlnuf', 11)
        allow(main_table).to receive(:delete_row).with(42).and_return(false)
        coordinator = described_class.new(main_table_id, baserow_config, {})

        expect { coordinator.delete_dossier(12_345) }.to raise_error(/#{main_table_id}.*42/)
      end

      it 'efface toutes les lignes d\'un bloc réparties sur plusieurs pages' do
        enregistrer('dlnuf', 11)
        allow(bloc_table).to receive(:find_by_link_row_id).with('Dossier', 42)
                                                          .and_return([{ 'id' => 7 }, { 'id' => 8 }], [{ 'id' => 9 }], [])
        described_class.new(main_table_id, baserow_config, {}).delete_dossier(12_345)

        [7, 8, 9].each { |id| expect(bloc_table).to have_received(:delete_row).with(id) }
      end

      it 'efface toutes les lignes portant le numéro du dossier' do
        enregistrer('dlnuf', 11)
        allow(main_table).to receive(:find_by_normalized).with('Dossier', '12345')
                                                         .and_return([{ 'id' => 42 }, { 'id' => 43 }], [])
        allow(bloc_table).to receive(:find_by_link_row_id).with('Dossier', 43).and_return([])
        described_class.new(main_table_id, baserow_config, {}).delete_dossier(12_345)

        expect(main_table).to have_received(:delete_row).with(42)
        expect(main_table).to have_received(:delete_row).with(43)
      end

      it 'lève quand Baserow liste encore exactement les lignes principales qui viennent d\'être effacées' do
        enregistrer('dlnuf', 11)
        allow(main_table).to receive(:find_by_normalized).with('Dossier', '12345').and_return([{ 'id' => 42 }])
        coordinator = described_class.new(main_table_id, baserow_config, {})

        expect { Timeout.timeout(2) { coordinator.delete_dossier(12_345) } }
          .to raise_error(RuntimeError, /Effacement Baserow sans effet.*#{main_table_id}.*42/)
        expect(main_table).to have_received(:delete_row).with(42).once
      end

      it 'lève quand Baserow liste encore exactement les lignes de bloc qui viennent d\'être effacées' do
        enregistrer('dlnuf', 11)
        allow(bloc_table).to receive(:find_by_link_row_id).with('Dossier', 42).and_return([{ 'id' => 7 }, { 'id' => 8 }])
        coordinator = described_class.new(main_table_id, baserow_config, {})

        expect { Timeout.timeout(2) { coordinator.delete_dossier(12_345) } }
          .to raise_error(RuntimeError, /Effacement Baserow sans effet.*200.*7, 8/)
        expect(main_table).not_to have_received(:delete_row)
      end

      it 'n\'efface rien en archive' do
        champs[0]['description'] = nil
        coordinator = described_class.new(main_table_id, baserow_config, {})

        expect(coordinator.delete_dossier(12_345)).to be(false)
        expect(main_table).not_to have_received(:find_by_normalized)
        expect(main_table).not_to have_received(:delete_row)
        expect(bloc_table).not_to have_received(:delete_row)
      end

      it 'rend false sans erreur quand le dossier n\'a pas de ligne' do
        enregistrer('dlnuf', 11)
        allow(main_table).to receive(:find_by_normalized).with('Dossier', '12345').and_return([])
        coordinator = described_class.new(main_table_id, baserow_config, {})

        expect(coordinator.delete_dossier(12_345)).to be(false)
        expect(main_table).not_to have_received(:delete_row)
        expect(bloc_table).not_to have_received(:delete_row)
      end
    end
  end
end
