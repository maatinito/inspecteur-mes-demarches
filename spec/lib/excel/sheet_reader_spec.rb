# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
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

  describe 'sanitization des noms de colonnes' do
    def noms(entetes)
      described_class.sanitize_noms(entetes)
    end

    it 'retire la ponctuation et réduit les espaces multiples' do
      expect(noms(['Concentrations (%)', "  Poids/Volume  total \n"]))
        .to eq(['Concentrations', 'Poids Volume total'])
    end

    it 'suffixe les doublons' do
      expect(noms(%w[Nom Nom Nom])).to eq(%w[Nom Nom_2 Nom_3])
    end

    it 'nomme les en-têtes vides par leur position' do
      expect(noms(['Nom', nil, ''])).to eq(%w[Nom Colonne_2 Colonne_3])
    end

    # Les apostrophes et traits d'union portent du sens dans les libellés
    # français, qui sont aussi des noms de colonnes Grist réels : les retirer
    # empêcherait le rattachement par nom (« Numéro d'arrêté », « Date d'arrivée »).
    it 'conserve accents, apostrophes, traits d’union et le signe degré' do
      expect(noms(["Numéro d'arrêté", 'Numéro d’arrêté', 'N° TAHITI', 'Sous-total']))
        .to eq(["Numéro d'arrêté", 'Numéro d’arrêté', 'N° TAHITI', 'Sous-total'])
    end

    it 's’applique aux colonnes lues, en conservant l’en-tête brut' do
      reader = described_class.new(fixture('entetes_tordus'), ligne_entete: 1)
      expect(reader.colonnes.map(&:nom)).to eq(['Nom', 'Nom_2', 'Colonne_3', 'Montant versé'])
      expect(reader.colonnes.last.en_tete_brut).to eq('Montant  versé')
      reader.close
    end

    it 'produit des clés de lignes cohérentes avec les noms sanitizés' do
      reader = described_class.new(fixture('preambule'))
      expect(reader.lignes.first.keys).to eq(['Substances actives', 'Concentrations', 'Poids Volume total'])
      reader.close
    end
  end

  describe 'inférence de type' do
    def type(valeurs)
      described_class.inferer_type(valeurs)
    end

    it { expect(type([1.5, 2.0])).to eq('Numeric') }
    it { expect(type([1, 2])).to eq('Int') }
    it { expect(type([Date.new(2026, 1, 1)])).to eq('Date') }
    it { expect(type([DateTime.new(2026, 1, 1, 8, 0)])).to eq('DateTime:UTC') }
    it { expect(type([true, false])).to eq('Bool') }

    it 'retombe sur Text pour une colonne mixte, pour ne jamais perdre de donnée' do
      expect(type(['a', 1])).to eq('Text')
      expect(type([1, 2.5])).to eq('Text')
    end

    it 'retombe sur Text pour une colonne vide' do
      expect(type([])).to eq('Text')
      expect(type([nil, nil])).to eq('Text')
    end

    it 'ignore les nil pour juger de l’homogénéité' do
      expect(type([nil, 3, nil])).to eq('Int')
    end

    it 's’applique aux colonnes lues' do
      reader = described_class.new(fixture('simple'))
      expect(reader.colonnes.map { |c| [c.nom, c.type_infere] })
        .to eq([%w[Nom Text], %w[Montant Numeric]])
      reader.close
    end

    it 'classe en Text une colonne numérique contenant une valeur saisie en texte' do
      # « 1 010,50 » est lu comme String par roo : la colonne devient mixte donc
      # Text. C'est la coercition (via le type forcé du mapping) qui récupère la
      # valeur, jamais l'inférence.
      reader = described_class.new(fixture('preambule'))
      expect(reader.colonnes.map { |c| [c.nom, c.type_infere] })
        .to eq([['Substances actives', 'Text'], %w[Concentrations Numeric], ['Poids Volume total', 'Text']])
      reader.close
    end
  end

  describe '.coercer' do
    it 'accepte les nombres déjà typés' do
      expect(described_class.coercer(1200.5, 'Numeric')).to eq(1200.5)
      expect(described_class.coercer(3, 'Int')).to eq(3)
    end

    # Les insécables sont écrites en échappement : un caractère invisible dans
    # la source est illisible en revue et fragile au reformatage.
    it 'tolère espaces, espaces insécables et virgule décimale' do
      expect(described_class.coercer('1 010,50', 'Numeric')).to eq(1010.5)
      expect(described_class.coercer("1\u00A0010,50", 'Numeric')).to eq(1010.5)
      expect(described_class.coercer("1\u202F010,50", 'Numeric')).to eq(1010.5)
      expect(described_class.coercer('1 010.50', 'Numeric')).to eq(1010.5)
    end

    it 'tronque vers Int quand le type cible est entier' do
      expect(described_class.coercer('1 010,50', 'Int')).to eq(1010)
    end

    it 'renvoie nil sur texte non numérique plutôt que zéro' do
      # Zéro serait un faux chiffre injecté dans un calcul : nil est honnête.
      expect(described_class.coercer('néant', 'Numeric')).to be_nil
      expect(described_class.coercer('', 'Numeric')).to be_nil
      expect(described_class.coercer(nil, 'Numeric')).to be_nil
    end

    it 'laisse intacte toute valeur dont la cible n’est pas numérique' do
      expect(described_class.coercer('1 010,50', 'Text')).to eq('1 010,50')
      expect(described_class.coercer('Kg', 'Choice')).to eq('Kg')
      expect(described_class.coercer(nil, 'Text')).to be_nil
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
# rubocop:enable Metrics/BlockLength
