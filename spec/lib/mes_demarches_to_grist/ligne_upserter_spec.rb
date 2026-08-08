# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MesDemarchesToGrist::LigneUpserter do
  let(:metadata_ref) do
    {
      'Dossier' => { id: 'Dossier', type: 'Ref:Dossiers' },
      'Ligne' => { id: 'Ligne', type: 'Int' }
    }
  end
  let(:metadata_int) do
    {
      'Dossier' => { id: 'Dossier', type: 'Int' },
      'Ligne' => { id: 'Ligne', type: 'Int' }
    }
  end
  let(:table) { instance_double(Grist::Table) }

  before { allow(table).to receive(:upsert_records) }

  describe '#upsert_lignes' do
    subject(:upserter) { described_class.new(table, field_metadata: metadata_ref) }

    it 'upserte chaque ligne avec la clé (Dossier, Ligne)' do
      upserter.upsert_lignes(617_871, [{ 'Nom' => 'A' }, { 'Nom' => 'B' }])

      expect(table).to have_received(:upsert_records) do |records|
        expect(records.size).to eq(2)
        expect(records.first[:require]).to eq('Dossier' => ['l', 617_871], 'Ligne' => 1)
        expect(records.last[:require]).to eq('Dossier' => ['l', 617_871], 'Ligne' => 2)
        expect(records.first[:fields]['Nom']).to eq('A')
      end
    end

    it 'écrit aussi la clé dans les champs, pour une ligne créée' do
      upserter.upsert_lignes(617_871, [{ 'Nom' => 'A' }])

      expect(table).to have_received(:upsert_records) do |records|
        expect(records.first[:fields]['Dossier']).to eq(['l', 617_871])
        expect(records.first[:fields]['Ligne']).to eq(1)
      end
    end

    it 'laisse la clé brute quand la colonne Dossier n’est pas une référence' do
      described_class.new(table, field_metadata: metadata_int).upsert_lignes(617_871, [{ 'Nom' => 'A' }])

      expect(table).to have_received(:upsert_records) do |records|
        expect(records.first[:require]['Dossier']).to eq(617_871)
      end
    end

    it 'renvoie le nombre de lignes écrites' do
      expect(upserter.upsert_lignes(617_871, [{ 'Nom' => 'A' }, { 'Nom' => 'B' }])).to eq(2)
    end

    it 'n’appelle pas Grist pour une liste vide' do
      expect(table).not_to receive(:upsert_records)
      expect(upserter.upsert_lignes(617_871, [])).to eq(0)
    end

    # La clé étant l'index de ligne, deux lignes source identiques restent deux
    # lignes distinctes et un re-run réécrit les mêmes clés : aucun besoin de
    # dédoublonner, contrairement au workflow n8n qui dédoublonnait sur 4 clés
    # métier avant l'upsert.
    it 'conserve des lignes source identiques comme des lignes distinctes' do
      upserter.upsert_lignes(617_871, [{ 'Nom' => 'A' }, { 'Nom' => 'A' }])

      expect(table).to have_received(:upsert_records) do |records|
        expect(records.map { |r| r[:require]['Ligne'] }).to eq([1, 2])
      end
    end

    it 'produit exactement les mêmes clés à deux passages successifs' do
      cles = []
      allow(table).to receive(:upsert_records) { |records| cles << records.map { |r| r[:require] } }

      upserter.upsert_lignes(617_871, [{ 'Nom' => 'A' }])
      upserter.upsert_lignes(617_871, [{ 'Nom' => 'A' }])

      expect(cles.first).to eq(cles.last)
    end
  end

  describe '#supprimer_orphelins' do
    subject(:upserter) { described_class.new(table, field_metadata: metadata_ref) }

    before do
      allow(table).to receive(:find_by).with('Dossier', ['l', 617_871]).and_return([
                                                                                     { 'id' => 10, 'fields' => { 'Ligne' => 1 } },
                                                                                     { 'id' => 11, 'fields' => { 'Ligne' => 2 } },
                                                                                     { 'id' => 12, 'fields' => { 'Ligne' => 3 } }
                                                                                   ])
      allow(table).to receive(:delete_records)
    end

    # Sans cette étape, un fichier corrigé à la baisse laisse des lignes
    # fantômes : c'est le cas du workflow n8n, qui ne supprime jamais rien.
    it 'supprime les lignes au-delà du nombre courant' do
      expect(upserter.supprimer_orphelins(617_871, 1)).to eq(2)
      expect(table).to have_received(:delete_records).with([11, 12])
    end

    it 'ne supprime rien quand le fichier n’a pas rétréci' do
      expect(upserter.supprimer_orphelins(617_871, 3)).to eq(0)
      expect(table).not_to have_received(:delete_records)
    end

    it 'supprime tout quand le fichier ne contient plus aucune ligne' do
      expect(upserter.supprimer_orphelins(617_871, 0)).to eq(3)
      expect(table).to have_received(:delete_records).with([10, 11, 12])
    end
  end
end
