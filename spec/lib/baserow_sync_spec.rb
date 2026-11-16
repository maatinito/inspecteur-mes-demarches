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
             instructeurs: [],
             traitements: [],
             groupe_instructeur: nil,
             date_depot: nil,
             date_passage_en_instruction: nil,
             date_traitement: nil,
             date_suppression_par_usager: nil)
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

  describe 'dossier supprimé par l\'usager et hook deleted' do
    let(:demarche) { double('Demarche', id: 999) }
    let(:params) { { baserow: { 'table_id' => 100 }, etat_du_dossier: 'en_instruction' } }
    let(:checker) { described_class.new(params) }
    let(:coordinator) { instance_double(MesDemarchesToBaserow::SyncCoordinator, mode: :dlnuf, demarche_number: 999, delete_dossier: true, sync_dossier: nil) }
    let(:supprime_le) { Time.zone.parse('2026-11-01 10:00') }
    let(:dossier) do
      double('Dossier', number: 12_345, state: 'accepte', date_suppression_par_usager: supprime_le)
    end

    before { allow(MesDemarchesToBaserow::SyncCoordinator).to receive(:new).and_return(coordinator) }

    it 'efface la ligne d\'un dossier supprimé par l\'usager en DLNUF, même hors du filtre etat_du_dossier' do
      checker.process(demarche, dossier)

      expect(coordinator).to have_received(:delete_dossier).with(12_345)
      expect(coordinator).not_to have_received(:sync_dossier)
    end

    it 'synchronise normalement un dossier supprimé par l\'usager en archive' do
      allow(coordinator).to receive(:mode).and_return(:archive)
      dossier = double('Dossier', number: 12_345, state: 'en_instruction', date_suppression_par_usager: supprime_le)

      checker.process(demarche, dossier)

      expect(coordinator).not_to have_received(:delete_dossier)
      expect(coordinator).to have_received(:sync_dossier).with(dossier)
    end

    it 'recrée la ligne quand dateSuppressionParUsager est redevenu vide' do
      dossier = double('Dossier', number: 12_345, state: 'en_instruction', date_suppression_par_usager: nil)

      checker.process(demarche, dossier)

      expect(coordinator).not_to have_received(:delete_dossier)
      expect(coordinator).to have_received(:sync_dossier).with(dossier)
    end

    it 'ne construit pas de coordinateur pour un dossier ordinaire écarté par le filtre' do
      dossier = double('Dossier', number: 12_345, state: 'accepte', date_suppression_par_usager: nil)

      checker.process(demarche, dossier)

      expect(MesDemarchesToBaserow::SyncCoordinator).not_to have_received(:new)
    end

    it 'BaserowSync#deleted laisse remonter un refus du verrou' do
      allow(coordinator).to receive(:delete_dossier).and_raise(Referentiel::Verrou::Refus.new('test'))

      expect { checker.deleted(demarche, 12_345) }.to raise_error(Referentiel::Verrou::Refus)
    end

    it 'BaserowSync#deleted laisse remonter une erreur ordinaire' do
      allow(coordinator).to receive(:delete_dossier).and_raise('boum')

      expect { checker.deleted(demarche, 12_345) }.to raise_error('boum')
    end

    describe '#ecoute_suppressions?' do
      def enregistrer(mode, table_ref: '100', backend: 'baserow')
        ReferentielTable.create!(backend:, table_ref:, mode:, proprietaire: mode == 'dlnuf' ? 7 : nil)
      end

      it 'est faux sans enregistrement, sans construire de coordinateur' do
        expect(checker.ecoute_suppressions?(demarche)).to be(false)
        expect(MesDemarchesToBaserow::SyncCoordinator).not_to have_received(:new)
      end

      it 'est faux pour une table enregistrée en archive' do
        enregistrer('archive')
        expect(checker.ecoute_suppressions?(demarche)).to be(false)
      end

      it 'est faux pour une table de type encore inconnu' do
        enregistrer('inconnu')
        expect(checker.ecoute_suppressions?(demarche)).to be(false)
      end

      it 'est faux pour une table DLNUF d\'un autre backend ou d\'une autre table' do
        enregistrer('dlnuf', backend: 'grist')
        enregistrer('dlnuf', table_ref: '101')
        expect(checker.ecoute_suppressions?(demarche)).to be(false)
      end

      it 'est vrai pour la table configurée enregistrée en DLNUF' do
        enregistrer('dlnuf')
        expect(checker.ecoute_suppressions?(demarche)).to be(true)
        expect(MesDemarchesToBaserow::SyncCoordinator).not_to have_received(:new)
      end
    end

    it 'BaserowSync#deleted délègue au coordinateur de la démarche' do
      checker.deleted(demarche, 12_345)

      expect(MesDemarchesToBaserow::SyncCoordinator).to have_received(:new).with(999, params[:baserow], {})
      expect(coordinator).to have_received(:delete_dossier).with(12_345)
    end
  end

  describe 'configuration du mapping' do
    def tache(mapping)
      described_class.new(baserow: { 'table_id' => 1 }, mapping:)
    end

    it 'refuse une valeur qui n\'est ni un stable_id ni un gabarit' do
      expect(tache('A' => [1]).errors.join).to include('ni un stable_id')
    end

    it 'accepte stable_id et gabarit' do
      expect(tache('A' => 140_066, 'B' => 'DIREN').errors).to be_empty
    end

    it 'transmet le mapping et un gabarit instancié par la tâche au coordinateur' do
      coordinateur = instance_double(MesDemarchesToBaserow::SyncCoordinator, demarche_number: 999, delete_dossier: true)
      gabarit = nil
      allow(MesDemarchesToBaserow::SyncCoordinator).to receive(:new) do |*_args, **kwargs|
        gabarit = kwargs[:gabarit]
        coordinateur
      end

      tache('Service' => 'DIREN').deleted(double('Demarche', id: 999), 1)

      expect(MesDemarchesToBaserow::SyncCoordinator).to have_received(:new)
        .with(999, { 'table_id' => 1 }, {}, mapping: { 'Service' => 'DIREN' }, gabarit: kind_of(Proc))
      expect(gabarit.call('DIREN')).to eq('DIREN')
    end
  end
end
# rubocop:enable Metrics/BlockLength
