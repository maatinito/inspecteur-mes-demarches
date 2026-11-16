# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MesDemarchesToBaserow::Mapping do
  let(:metadata) do
    { 'Service' => { 'type' => 'single_select' }, 'Représentant nom' => { 'type' => 'text' },
      'Statuts' => { 'type' => 'text', 'reference_pj' => true }, 'Début de mandat' => { 'type' => 'date' } }
  end
  let(:champs) { { 140_066 => 'NOM Président(e)', 140_102 => 'Statuts en vigueur', 150_001 => 'Adresse postale' } }
  let(:annotations) { { 160_000 => 'Montant accordé' } }

  def mapping(config)
    described_class.new(config, field_metadata: metadata, champs:, annotations:)
  end

  it 'retient un stable_id et une constante sur single_select' do
    m = mapping('Représentant nom' => 140_066, 'Service' => 'DIREN')
    expect(m.entrees.map(&:to_a)).to contain_exactly(['Représentant nom', 140_066, nil], ['Service', nil, 'DIREN'])
    expect(m.avertissements).to be_empty
  end

  it 'ignore une colonne absente de la table' do
    m = mapping('Inconnue' => 140_066)
    expect(m.entrees).to be_empty
    expect(m.avertissements.first).to include('Inconnue')
  end

  it 'ignore un gabarit sur une colonne date' do
    m = mapping('Début de mandat' => '{Adresse postale}')
    expect(m.entrees).to be_empty
    expect(m.avertissements.first).to include('Début de mandat')
  end

  it 'accepte un stable_id sur une colonne date' do
    expect(mapping('Début de mandat' => 140_066).entrees.size).to eq(1)
  end

  it 'ignore un stable_id inconnu de la démarche' do
    m = mapping('Représentant nom' => 999)
    expect(m.entrees).to be_empty
    expect(m.avertissements.first).to include('999')
  end

  it 'ignore un stable_id d\'annotation privée' do
    m = mapping('Représentant nom' => 160_000)
    expect(m.entrees).to be_empty
    expect(m.avertissements.first).to include('annotation')
  end

  it 'ignore un gabarit dont un libellé est inconnu' do
    m = mapping('Représentant nom' => '{Adresse postale}{, ;Inconnu}')
    expect(m.entrees).to be_empty
    expect(m.avertissements.first).to include('Inconnu')
  end

  it 'accepte les libellés connus, avec préfixe/suffixe, ternaire ou annotation' do
    m = mapping('Représentant nom' => '{Adresse postale ? oui : non}{BP ;Montant accordé; F}')
    expect(m.entrees.size).to eq(1)
    expect(m.avertissements).to be_empty
  end

  it 'garde une chaîne numérique comme constante mais avertit' do
    m = mapping('Représentant nom' => '140066')
    expect(m.entrees.first.gabarit).to eq('140066')
    expect(m.avertissements.first).to include('stable_id')
  end

  describe '.erreurs_de_config' do
    it { expect(described_class.erreurs_de_config('x')).not_to be_empty }
    it { expect(described_class.erreurs_de_config('A' => 1.5)).not_to be_empty }
    it { expect(described_class.erreurs_de_config('A' => 1, 'B' => 'x')).to be_empty }
  end
end
