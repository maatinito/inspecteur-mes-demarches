# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Excel::SheetReader do
  def fixture(nom)
    Rails.root.join("spec/fixtures/excel/#{nom}.xlsx").to_s
  end

  describe '.noms_feuilles' do
    it 'liste les feuilles dans l’ordre du document' do
      expect(described_class.noms_feuilles(fixture('multi_feuilles'))).to eq(%w[Garde Donnees])
    end
  end

  describe 'sélection de feuille' do
    it 'lit la première feuille par défaut' do
      reader = described_class.new(fixture('simple'))
      expect(reader.nom_feuille).to eq('Feuille1')
      expect(reader.colonnes.map(&:nom)).to eq(%w[Nom Montant])
      expect(reader.lignes).to eq([
                                    { 'Nom' => 'Dupont', 'Montant' => 1200.5 },
                                    { 'Nom' => 'Martin', 'Montant' => 300.0 }
                                  ])
      reader.close
    end

    it 'sélectionne une feuille par nom' do
      reader = described_class.new(fixture('multi_feuilles'), feuille: 'Donnees')
      expect(reader.lignes).to eq([{ 'Code' => 'A1', 'Libelle' => 'Alpha' }])
      reader.close
    end

    it 'sélectionne une feuille par position 1-based' do
      reader = described_class.new(fixture('multi_feuilles'), feuille: 2)
      expect(reader.nom_feuille).to eq('Donnees')
      reader.close
    end

    it 'lève une erreur explicite sur feuille introuvable' do
      expect { described_class.new(fixture('multi_feuilles'), feuille: 'Absente') }
        .to raise_error(described_class::FeuilleIntrouvable, /Absente.*Garde, Donnees/)
    end

    it 'lève une erreur explicite sur position hors bornes' do
      expect { described_class.new(fixture('multi_feuilles'), feuille: 9) }
        .to raise_error(described_class::FeuilleIntrouvable, /9/)
    end
  end

  describe "détection de la ligne d'en-tête" do
    it 'traverse un préambule pour trouver la ligne d’en-tête' do
      reader = described_class.new(fixture('preambule'))
      expect(reader.ligne_entete).to eq(5)
      expect(reader.lignes.size).to eq(2)
      reader.close
    end

    it 'accepte une ligne d’en-tête forcée' do
      # Cas pathologique : l'en-tête porte un trou, l'heuristique désignerait la
      # ligne 2. La détection avancée est hors périmètre (spec §2), on force.
      reader = described_class.new(fixture('entetes_tordus'), ligne_entete: 1)
      expect(reader.ligne_entete).to eq(1)
      expect(reader.lignes.size).to eq(1)
      reader.close
    end
  end

  describe 'lignes de données' do
    it 'ignore les lignes antérieures à l’en-tête et les lignes vides' do
      reader = described_class.new(fixture('preambule'))
      expect(reader.lignes.map { |l| l['Substances actives'] }).to eq(%w[Géraniol Chlorure])
      reader.close
    end

    it 'conserve une ligne dont une colonne autre que la première est vide' do
      # GetSheets testait row[1] (la 2e cellule) pour décider si la ligne porte
      # des données : une 2e colonne vide écartait la ligne à tort.
      reader = described_class.new(fixture('colonne_vide'))
      expect(reader.lignes.size).to eq(2)
      expect(reader.lignes.last['Montant']).to be_nil
      reader.close
    end
  end
end
