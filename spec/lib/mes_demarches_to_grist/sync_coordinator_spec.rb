# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe MesDemarchesToGrist::SyncCoordinator do
  # Colonnes indexées par id, comme les renvoie Grist::Table#columns.
  let(:columns) do
    {
      'Dossier' => { id: 'Dossier', label: 'Dossier', type: 'Int', isFormula: false },
      'statut' => { id: 'statut', label: 'Statut', type: 'Choice', isFormula: false },
      'importateur' => { id: 'importateur', label: 'Importateur', type: 'Text', isFormula: false }
    }
  end

  let(:client) { instance_double(Grist::Client) }
  let(:table) { instance_double(Grist::Table, columns: columns, client: client) }
  let(:grist_config) { { 'doc_id' => 'doc', 'table_id' => 'Dossiers' } }

  # Un dossier minimal : les métadonnées de SchemaBuilders::MetadataFields sont
  # lues sur cet objet, il doit donc répondre à toute la surface système.
  def dossier_double(number: 617_871, champs: [], state: 'accepte')
    double('dossier',
           number: number,
           state: state,
           champs: champs,
           annotations: [],
           demandeur: double('demandeur', __typename: 'PersonnePhysique', civilite: nil, nom: nil, prenom: nil),
           date_depot: nil,
           date_passage_en_instruction: nil,
           date_traitement: nil,
           usager: nil,
           groupe_instructeur: nil,
           labels: [])
  end

  def champ_double(label:, value:, typename: 'TextChamp')
    double('champ', label: label, __typename: typename, value: value)
  end

  before do
    allow(Grist::Config).to receive(:table).and_return(table)
    # SyncCoordinator#process_file_uploads construit un FileUploader via
    # Grist::Config.client, qui lit ENV['GRIST_API_KEY'] : sans ce bouchon le
    # test exige un vrai identifiant, donc passe en local et casse en CI.
    allow(Grist::Config).to receive(:client).and_return(client)
    allow(table).to receive(:upsert_records)
    allow(table).to receive(:find_by).and_return([])
    allow(client).to receive(:list_tables).and_return({ 'tables' => [] })
  end

  subject(:coordinator) { described_class.new(1536, grist_config, {}) }

  it 'upserte la ligne principale avec la clé Dossier' do
    coordinator.sync_dossier(dossier_double)

    expect(table).to have_received(:upsert_records) do |records|
      expect(records.size).to eq(1)
      expect(records.first[:require]).to eq('Dossier' => 617_871)
    end
  end

  it 'convertit les libellés de champs en identifiants de colonnes Grist' do
    dossier = dossier_double(champs: [champ_double(label: 'Importateur', value: 'Faaa Matériaux')])

    coordinator.sync_dossier(dossier)

    expect(table).to have_received(:upsert_records) do |records|
      expect(records.first[:fields]['importateur']).to eq('Faaa Matériaux')
    end
  end

  it 'ignore les champs sans colonne correspondante dans la table' do
    dossier = dossier_double(champs: [champ_double(label: 'Champ inconnu', value: 'x')])

    coordinator.sync_dossier(dossier)

    expect(table).to have_received(:upsert_records) do |records|
      expect(records.first[:fields].keys).not_to include('Champ inconnu')
    end
  end

  it "n'upserte pas quand aucune valeur n'a changé" do
    existant = { 'id' => 3, 'fields' => { 'Dossier' => 617_871, 'statut' => 'accepte' } }
    allow(table).to receive(:find_by).with('Dossier', 617_871).and_return([existant])

    coordinator.sync_dossier(dossier_double)

    expect(table).not_to have_received(:upsert_records)
  end

  it 'remonte le statut du dossier dans la colonne dédiée' do
    coordinator.sync_dossier(dossier_double(state: 'en_instruction'))

    expect(table).to have_received(:upsert_records) do |records|
      expect(records.first[:fields]['statut']).to eq('en_instruction')
    end
  end

  # Cas d'une table dont la colonne Dossier est une référence : la recherche de
  # la ligne existante doit filtrer sur la forme encodée, sinon elle ne matche
  # jamais et chaque passage recrée une ligne.
  context 'quand la colonne Dossier de la table est une référence' do
    let(:columns) do
      {
        'Dossier' => { id: 'Dossier', label: 'Dossier', type: 'Ref:Dossiers', isFormula: false },
        'importateur' => { id: 'importateur', label: 'Importateur', type: 'Text', isFormula: false }
      }
    end

    it 'recherche la ligne existante avec la clé encodée' do
      coordinator.sync_dossier(dossier_double)

      # Deux appels attendus : recherche de la ligne existante par le
      # coordinateur, puis relecture de l'id par RowUpserter après l'upsert.
      expect(table).to have_received(:find_by).with('Dossier', ['l', 617_871]).at_least(:once)
    end
  end

  # Grist dérive l'id d'une table de son nom en gardant la casse
  # (« Rubriques concernées ICPE » → Rubriques_concernees_ICPE) : la recherche de
  # la table d'un bloc ne doit dépendre ni de la casse ni des accents.
  context 'avec un bloc répétable' do
    let(:block_columns) do
      {
        'Dossier' => { id: 'Dossier', label: 'Dossier', type: 'Ref:Dossiers', isFormula: false },
        'Ligne' => { id: 'Ligne', label: 'Ligne', type: 'Int', isFormula: false },
        'rubrique' => { id: 'rubrique', label: 'Rubrique', type: 'Text', isFormula: false }
      }
    end
    let(:block_table) { instance_double(Grist::Table, columns: block_columns, client: client) }
    let(:extractor) { instance_double(MesDemarchesToGrist::DataExtractor) }

    before do
      allow(client).to receive(:list_tables).and_return({ 'tables' => [{ 'id' => 'Dossiers' }, { 'id' => 'Rubriques_concernees_ICPE' }] })
      allow(Grist::Config).to receive(:table).with('doc', 'Rubriques_concernees_ICPE', nil).and_return(block_table)
      allow(block_table).to receive(:find_by).and_return([])
      allow(block_table).to receive(:upsert_records)
      allow(table).to receive(:find_by).and_return([{ 'id' => 7, 'fields' => {} }])
      allow(MesDemarchesToGrist::DataExtractor).to receive(:new).and_return(extractor)
      allow(extractor).to receive(:extract_all).and_return(
        main_table: { 'Dossier' => 617_871, 'Statut' => 'accepte' },
        repetable_blocks: { 'Rubriques concernées ICPE' => [{ 'Ligne' => 1, 'Rubrique' => '1510', 'Commune' => 'Papeete' }] }
      )
    end

    it 'retrouve la table du bloc malgré la casse et les accents' do
      coordinator.sync_dossier(dossier_double)

      expect(block_table).to have_received(:upsert_records) do |records|
        expect(records.first[:fields]).to include('rubrique' => '1510', 'Dossier' => 7)
      end
    end

    # Un champ du bloc exclu à la construction n'a pas de colonne : Grist
    # refuserait toute la ligne (« Invalid column »), on l'ignore comme pour la
    # table principale.
    it 'ignore les champs du bloc sans colonne dans la table' do
      coordinator.sync_dossier(dossier_double)

      expect(block_table).to have_received(:upsert_records) do |records|
        expect(records.first[:fields].keys).not_to include('Commune')
      end
    end
  end
  # Bout en bout avec le vrai extracteur : la colonne « Rubrique – numero » de
  # la table du bloc reçoit la colonne du référentiel, convertie en entier.
  context 'avec un référentiel de Polynésie dans un bloc' do
    let(:block_columns) do
      {
        'Dossier' => { id: 'Dossier', label: 'Dossier', type: 'Ref:Dossiers', isFormula: false },
        'Ligne' => { id: 'Ligne', label: 'Ligne', type: 'Int', isFormula: false },
        'Rubrique_numero' => { id: 'Rubrique_numero', label: 'Rubrique – numero', type: 'Int', isFormula: false }
      }
    end
    let(:block_table) { instance_double(Grist::Table, columns: block_columns, client: client) }
    let(:rubrique) do
      double('ReferentielDePolynesieChamp', __typename: 'ReferentielDePolynesieChamp', label: 'Rubrique',
                                            string_value: '2131-c', value: '2131-c',
                                            columns: [double(name: 'numero', value: '2131')])
    end
    let(:bloc) do
      double('RepetitionChamp', __typename: 'RepetitionChamp', label: 'Rubriques', rows: [double('row', champs: [rubrique])])
    end

    before do
      allow(client).to receive(:list_tables).and_return({ 'tables' => [{ 'id' => 'Dossiers' }, { 'id' => 'Rubriques' }] })
      allow(Grist::Config).to receive(:table).with('doc', 'Rubriques', nil).and_return(block_table)
      allow(block_table).to receive(:find_by).and_return([])
      allow(block_table).to receive(:upsert_records)
      allow(table).to receive(:find_by).and_return([{ 'id' => 7, 'fields' => {} }])
    end

    it 'remplit la sous-colonne de la table du bloc' do
      coordinator.sync_dossier(dossier_double(champs: [bloc]))

      expect(block_table).to have_received(:upsert_records) do |records|
        expect(records.first[:fields]).to include('Rubrique_numero' => 2131)
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
