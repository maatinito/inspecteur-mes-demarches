# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CulturesParFamille do
  let(:controle) do
    described_class.new(champ: 'Cultures sur ces parcelles', bloc_destination: 'Cultures par famille',
                        familles: { 'Bananiers/fei': ['banane fei', 'fei'], Vanille: ['vanille'],
                                    'Cultures maraîchères et horticoles': ['tomate', 'pépinière maraichère, aromatique'] })
  end
  let(:demarche) { double('Demarche', instructeur: 'instructeur') }
  let(:source) do
    double('Champ', __typename: 'MultipleDropDownListChamp', label: 'Cultures sur ces parcelles',
                    string_value: 'vanille, tomate, banane fei, pépinière maraichère, aromatique, kava')
  end
  let(:dossier) { double('Dossier', id: 'D1', number: 1, state: 'en_construction', champs: [source], annotations: [bloc]) }
  let(:rows) { [row('Vanille', 'vanille'), row('ancienne', 'x')] }
  let(:bloc) { double('Bloc', label: 'Cultures par famille', rows:) }

  def row(famille = nil, cultures = nil)
    double('Row', champs: [
             double('Champ', id: SecureRandom.hex(4), label: 'Famille', __typename: 'TextChamp', value: famille),
             double('Champ', id: SecureRandom.hex(4), label: 'Cultures', __typename: 'TextChamp', value: cultures)
           ])
  end

  before do
    allow(SetAnnotationValue).to receive(:allocate_blocks).and_return(bloc)
    allow(SetAnnotationValue).to receive(:raw_set_value)
  end

  def ecrit?(row, colonne, valeur)
    expect(SetAnnotationValue).to have_received(:raw_set_value).with('D1', 'instructeur', rows[row].champs[colonne].id, valeur)
  end

  it 'writes one row per family, in the order of the configuration' do
    rows.push(row, row)
    controle.process(demarche, dossier)
    expect(SetAnnotationValue).to have_received(:allocate_blocks).with(dossier, 'instructeur', 'Cultures par famille', 4)
    ecrit?(0, 0, 'Bananiers/fei')
    ecrit?(0, 1, 'banane fei')
    ecrit?(1, 0, 'Vanille')
    ecrit?(1, 1, 'vanille')
    ecrit?(2, 0, 'Cultures maraîchères et horticoles')
    ecrit?(2, 1, 'tomate, pépinière maraichère, aromatique')
    ecrit?(3, 0, 'Autres')
    ecrit?(3, 1, 'kava')
    expect(SetAnnotationValue).to have_received(:raw_set_value).exactly(8).times
    expect(controle.dossier_updated?).to be true
  end

  it 'clears the rows of families no longer selected' do
    allow(source).to receive(:string_value).and_return('vanille')
    controle.process(demarche, dossier)
    ecrit?(1, 0, '')
    ecrit?(1, 1, '')
  end

  it 'does nothing when nothing changed' do
    allow(source).to receive(:string_value).and_return('vanille')
    rows.pop
    controle.process(demarche, dossier)
    expect(SetAnnotationValue).not_to have_received(:raw_set_value)
    expect(controle.dossier_updated?).to be false
  end
end
