# frozen_string_literal: true

require 'rails_helper'

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
end
