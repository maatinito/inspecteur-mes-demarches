# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChampsComposites do
  def referentiel(label, columns, string_value: 'x')
    double('ReferentielDePolynesieChamp', __typename: 'ReferentielDePolynesieChamp', label: label,
                                          string_value: string_value,
                                          columns: columns.map { |name, value| double('column', name: name, value: value) })
  end

  def siret(label, etablissement)
    double('SiretChamp', __typename: 'SiretChamp', label: label, etablissement: etablissement)
  end

  def commune(label, commune)
    double('CommuneDePolynesieChamp', __typename: 'CommuneDePolynesieChamp', label: label, commune: commune)
  end

  def texte(label)
    double('TextChamp', __typename: 'TextChamp', label: label)
  end

  describe '.rapprocher' do
    let(:rubrique) { referentiel('Rubrique concernée', { 'classe' => '2ème classe' }) }

    it 'rapproche une colonne « Libellé – sous-colonne » (demi-cadratin)' do
      expect(described_class.rapprocher(['Rubrique concernée – classe'], [rubrique]))
        .to eq('Rubrique concernée – classe' => [rubrique, 'classe'])
    end

    it 'accepte le tiret simple, que les agents tapent au clavier' do
      expect(described_class.rapprocher(['Rubrique concernée - classe'], [rubrique]))
        .to eq('Rubrique concernée - classe' => [rubrique, 'classe'])
    end

    it "laisse au champ entier une colonne dont le libellé est exactement celui d'un champ" do
      homonyme = texte('Rubrique concernée - classe')

      expect(described_class.rapprocher(['Rubrique concernée - classe'], [rubrique, homonyme])).to eq({})
    end

    it 'retient le libellé de champ le plus long quand le libellé contient lui-même un tiret' do
      long = referentiel('Rubrique - ICPE', { 'classe' => 'A' })

      expect(described_class.rapprocher(['Rubrique - ICPE - classe'], [long]))
        .to eq('Rubrique - ICPE - classe' => [long, 'classe'])
    end

    it 'ignore les champs qui ne sont pas composites et les colonnes sans correspondance' do
      expect(described_class.rapprocher(['Nom - classe', 'Autre – classe'], [texte('Nom'), rubrique])).to eq({})
    end
  end

  describe '.valeur' do
    it "lit la colonne d'un référentiel sans tenir compte de la casse ni des accents" do
      champ = referentiel('R', { 'condition 1' => 'Ecloseries' })

      expect(described_class.valeur(champ, 'Condition 1')).to eq('Ecloseries')
    end

    it "signale une colonne de référentiel inconnue (la cellule n'est pas touchée)" do
      champ = referentiel('R', { 'classe' => 'A' })

      expect(described_class.valeur(champ, 'clase')).to eq(described_class::ABSENTE)
    end

    it 'renvoie nil pour un référentiel vide (la cellule est vidée)' do
      champ = referentiel('R', {}, string_value: '')

      expect(described_class.valeur(champ, 'classe')).to be_nil
    end

    it 'lit les informations du N° Tahiti avec les libellés du tableau instructeur' do
      etablissement = double('etablissement',
                             entreprise: double('entreprise', raison_sociale: 'BORA BORA PEARL', nom_commercial: 'LE BORA',
                                                              forme_juridique: 'SA', siren: '380618'),
                             libelle_naf: 'Hôtels', naf: '5510Z', address: double('address', label: 'BP 314'))
      champ = siret('N° TAHITI', etablissement)

      expect(described_class.valeur(champ, 'Entreprise raison sociale')).to eq('BORA BORA PEARL')
      expect(described_class.valeur(champ, 'Établissement NAF')).to eq('5510Z')
      expect(described_class.valeur(champ, 'Etablissement adresse')).to eq('BP 314')
    end

    it 'renvoie nil pour un N° Tahiti sans établissement' do
      expect(described_class.valeur(siret('N° TAHITI', nil), 'Entreprise raison sociale')).to be_nil
    end

    it "lit l'île et le code postal d'une commune (Ile ou Île)" do
      champ = commune('Commune', double('commune', name: 'Faanui', postal_code: 98_730, island: 'Bora-Bora',
                                                   archipelago: 'Iles Sous Le Vent'))

      expect(described_class.valeur(champ, 'Île')).to eq('Bora-Bora')
      expect(described_class.valeur(champ, 'Code postal')).to eq(98_730)
    end

    it 'lit la date de naissance du N° DN' do
      champ = double('NumeroDnChamp', __typename: 'NumeroDnChamp', label: 'DN', date_de_naissance: '1980-05-12')

      expect(described_class.valeur(champ, 'Date de naissance')).to eq('1980-05-12')
    end

    it "signale une sous-colonne inconnue d'un champ à structure fixe" do
      expect(described_class.valeur(siret('N° TAHITI', nil), 'Capital')).to eq(described_class::ABSENTE)
    end
  end

  describe 'conversions' do
    it 'lit les dates ISO et françaises' do
      expect(described_class.en_date('1980-05-12')).to eq(Date.new(1980, 5, 12))
      expect(described_class.en_date('12/05/1980')).to eq(Date.new(1980, 5, 12))
    end

    it 'lit les nombres avec virgule décimale et séparateurs de milliers' do
      expect(described_class.en_nombre('12,5')).to eq(12.5)
      expect(described_class.en_nombre('1 200')).to eq(1200)
      expect(described_class.en_nombre(98_730)).to eq(98_730)
    end

    it 'lit les booléens en français et en anglais' do
      expect(described_class.en_booleen('Vrai')).to be(true)
      expect(described_class.en_booleen('non')).to be(false)
    end

    it 'lève ArgumentError sur une valeur inconvertible' do
      expect { described_class.en_nombre('environ 20') }.to raise_error(ArgumentError)
      expect { described_class.en_date('bientôt') }.to raise_error(ArgumentError)
      expect { described_class.en_booleen('peut-être') }.to raise_error(ArgumentError)
    end
  end
end
