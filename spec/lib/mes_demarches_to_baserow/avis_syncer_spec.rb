# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe MesDemarchesToBaserow::AvisSyncer do
  let(:main_table_id) { 100 }
  let(:avis_table_id) { 200 }
  let(:application_tables) { { 'Avis' => avis_table_id } }

  let(:baserow_config) { { 'table_id' => main_table_id, 'token_config' => nil } }
  let(:options) { {} }

  let(:avis_field_metadata) do
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

  let(:field_metadata_loader) { ->(_id) { avis_field_metadata } }
  let(:structure_client) { instance_double(Baserow::StructureClient) }
  let(:avis_table) { instance_double(Baserow::Table) }

  let(:syncer) do
    described_class.new(
      application_tables: application_tables,
      main_table_id: main_table_id,
      baserow_config: baserow_config,
      options: options,
      field_metadata_loader: field_metadata_loader,
      structure_client: structure_client
    )
  end

  let(:dossier) { double('Dossier', number: 12_345) }
  let(:main_row_id) { 42 }
  let(:noop_uploader) { ->(_data, _meta) {} }

  # Liste de champs Baserow valide pour la table Avis (utilisée par
  # check_structure pour trouver primary + link via un seul get_table_fields).
  let(:valid_avis_fields) do
    [
      { 'name' => 'Avis', 'type' => 'text', 'primary' => true },
      { 'name' => 'Dossier', 'type' => 'link_row',
        'link_row_table_id' => main_table_id,
        'link_row_multiple_relationships' => false }
    ]
  end

  before do
    allow(Baserow::Config).to receive(:table).with(avis_table_id, anything).and_return(avis_table)
    allow(structure_client).to receive(:get_table_fields).with(avis_table_id).and_return(valid_avis_fields)
  end

  context 'quand la table Avis n\'existe pas dans l\'application' do
    let(:application_tables) { {} }

    it 'skip silencieusement (debug log)' do
      expect(Rails.logger).to receive(:debug).with(/Avis.*absente/)
      expect(MesDemarches::AvisFetcher).not_to receive(:fetch)
      syncer.sync(dossier, main_row_id, noop_uploader)
    end
  end

  context 'quand la structure de la table Avis est invalide (mauvais primary)' do
    let(:valid_avis_fields) do
      [
        { 'name' => 'Mauvais', 'type' => 'text', 'primary' => true },
        { 'name' => 'Dossier', 'type' => 'link_row',
          'link_row_table_id' => main_table_id,
          'link_row_multiple_relationships' => false }
      ]
    end

    it 'skip avec un warn explicite' do
      expect(Rails.logger).to receive(:warn).with(/structure invalide/)
      expect(MesDemarches::AvisFetcher).not_to receive(:fetch)
      syncer.sync(dossier, main_row_id, noop_uploader)
    end
  end

  context 'quand la structure de la table Avis a un link_row mal pointé' do
    let(:valid_avis_fields) do
      [
        { 'name' => 'Avis', 'type' => 'text', 'primary' => true },
        { 'name' => 'Dossier', 'type' => 'link_row',
          'link_row_table_id' => 999, # mauvaise table
          'link_row_multiple_relationships' => false }
      ]
    end

    it 'skip avec un warn mentionnant la mauvaise table' do
      expect(Rails.logger).to receive(:warn).with(/pointe vers table 999/)
      expect(MesDemarches::AvisFetcher).not_to receive(:fetch)
      syncer.sync(dossier, main_row_id, noop_uploader)
    end
  end

  context 'quand le link_row Dossier autorise plusieurs liens' do
    let(:valid_avis_fields) do
      [
        { 'name' => 'Avis', 'type' => 'text', 'primary' => true },
        { 'name' => 'Dossier', 'type' => 'link_row',
          'link_row_table_id' => main_table_id,
          'link_row_multiple_relationships' => true }
      ]
    end

    it 'skip avec un warn explicite' do
      expect(Rails.logger).to receive(:warn).with(/autorise plusieurs liens/)
      expect(MesDemarches::AvisFetcher).not_to receive(:fetch)
      syncer.sync(dossier, main_row_id, noop_uploader)
    end
  end

  context 'quand le champ Dossier est absent ou n\'est pas un link_row' do
    let(:valid_avis_fields) do
      [{ 'name' => 'Avis', 'type' => 'text', 'primary' => true }]
    end

    it 'skip avec un warn explicite' do
      expect(Rails.logger).to receive(:warn).with(/link_row manquant ou type incorrect/)
      expect(MesDemarches::AvisFetcher).not_to receive(:fetch)
      syncer.sync(dossier, main_row_id, noop_uploader)
    end
  end

  context 'quand le dossier a 2 avis et 0 row existante' do
    let(:avis1) do
      double('Avis', id: 'AV1', question: 'Q1', reponse: 'R1', question_label: nil, question_answer: nil,
                     date_question: nil, date_reponse: nil,
                     expert: nil, claimant: nil, attachments: [])
    end
    let(:avis2) do
      double('Avis', id: 'AV2', question: 'Q2', reponse: 'R2', question_label: nil, question_answer: nil,
                     date_question: nil, date_reponse: nil,
                     expert: nil, claimant: nil, attachments: [])
    end

    before do
      allow(MesDemarches::AvisFetcher).to receive(:fetch).with(12_345).and_return([avis1, avis2])
      allow(avis_table).to receive(:find_by_link_row_id).with('Dossier', main_row_id).and_return([])
      allow(avis_table).to receive(:create_row).and_return({ 'id' => 1 })
    end

    it 'crée 2 nouvelles rows' do
      expect(avis_table).to receive(:create_row).twice
      syncer.sync(dossier, main_row_id, noop_uploader)
    end
  end

  context 'quand un avis existe déjà avec le même ID' do
    let(:avis) do
      double('Avis', id: 'AV1', question: 'Q1 modifiée', reponse: 'R1', question_label: nil, question_answer: nil,
                     date_question: nil, date_reponse: nil,
                     expert: nil, claimant: nil, attachments: [])
    end
    let(:existing_row) { { 'id' => 555, 'Avis' => 'AV1', 'Question' => 'Q1' } }

    before do
      allow(MesDemarches::AvisFetcher).to receive(:fetch).and_return([avis])
      allow(avis_table).to receive(:find_by_link_row_id).and_return([existing_row])
    end

    it 'met à jour la row existante (pas de create)' do
      expect(avis_table).to receive(:update_row).with(555, hash_including('Question' => 'Q1 modifiée'))
      expect(avis_table).not_to receive(:create_row)
      syncer.sync(dossier, main_row_id, noop_uploader)
    end
  end

  context 'avec supprimer_orphelins activé (défaut)' do
    let(:avis_current) do
      double('Avis', id: 'AV1', question: 'Q', reponse: 'R', question_label: nil, question_answer: nil,
                     date_question: nil, date_reponse: nil,
                     expert: nil, claimant: nil, attachments: [])
    end
    let(:row_kept) { { 'id' => 1, 'Avis' => 'AV1' } }
    let(:row_orphan) { { 'id' => 2, 'Avis' => 'AV_OLD' } }

    before do
      allow(MesDemarches::AvisFetcher).to receive(:fetch).and_return([avis_current])
      allow(avis_table).to receive(:find_by_link_row_id).and_return([row_kept, row_orphan])
      allow(avis_table).to receive(:update_row)
    end

    it 'supprime la row dont l\'ID Avis n\'est plus dans la liste actuelle' do
      expect(avis_table).to receive(:delete_row).with(2)
      expect(avis_table).not_to receive(:delete_row).with(1)
      syncer.sync(dossier, main_row_id, noop_uploader)
    end
  end

  context 'mémoization de la validation de structure' do
    let(:avis) do
      double('Avis', id: 'AV1', question: 'Q', reponse: 'R', question_label: nil, question_answer: nil,
                     date_question: nil, date_reponse: nil,
                     expert: nil, claimant: nil, attachments: [])
    end

    before do
      allow(MesDemarches::AvisFetcher).to receive(:fetch).and_return([avis])
      allow(avis_table).to receive(:find_by_link_row_id).and_return([])
      allow(avis_table).to receive(:create_row).and_return({ 'id' => 1 })
    end

    it 'n\'appelle get_table_fields qu\'une seule fois sur plusieurs dossiers' do
      syncer.sync(dossier, main_row_id, noop_uploader)
      syncer.sync(dossier, main_row_id, noop_uploader)
      syncer.sync(dossier, main_row_id, noop_uploader)
      expect(structure_client).to have_received(:get_table_fields).with(avis_table_id).once
    end
  end
end
# rubocop:enable Metrics/BlockLength
