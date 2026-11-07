# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Catanat::ElevagesSinistres do
  let(:controle) { described_class.new(champ: 'Élevage sinistré', bloc_destination: 'Élevages indemnisés') }
  let(:demarche) { double('Demarche', instructeur: 'instructeur') }
  let(:poules) { 'Poules pondeuses et poulets de chair' }

  def perte(type, nombre, bio: false)
    double('Row', champs: [
             double('Champ', label: "Type d'élevage", __typename: 'DropDownListChamp', string_value: type, value: type),
             double('Champ', label: 'Élevage bio ?', __typename: 'YesNoChamp', checked: bio),
             double('Champ', label: "Nombre d'animaux perdus", __typename: 'IntegerNumberChamp', int_value: nombre)
           ])
  end

  let(:source) do
    double('Bloc', label: 'Élevage sinistré', __typename: 'RepetitionChamp', rows: [
             perte(poules, 40), perte('Bovins reproducteurs', 2), perte(poules, 10), perte(poules, 5, bio: true)
           ])
  end
  let(:rows) do
    Array.new(2) do
      double('Row', champs: [*described_class::COLONNES, *described_class::RETENUS].map do |label|
        entier = described_class::RETENUS.include?(label)
        double('Champ', id: SecureRandom.hex(4), label:, __typename: entier ? 'IntegerNumberChamp' : 'TextChamp', value: nil, int_value: nil)
      end)
    end
  end
  let(:bloc) { double('Bloc', label: 'Élevages indemnisés', rows:) }
  let(:dossier) { double('Dossier', id: 'D1', number: 1, state: 'en_construction', champs: [source], annotations: [bloc]) }

  before do
    allow(SetAnnotationValue).to receive(:allocate_blocks).and_return(bloc)
    allow(SetAnnotationValue).to receive(:raw_set_value)
    controle.dossier = dossier
    controle.process(demarche, dossier)
  end

  def ecrit?(ligne, label, valeur)
    champ = rows[ligne].champs.find { it.label == label }
    expect(SetAnnotationValue).to have_received(:raw_set_value).with('D1', 'instructeur', champ.id, valeur)
  end

  it 'writes one row per type of animal, bio and non bio side by side' do
    expect(SetAnnotationValue).to have_received(:allocate_blocks).with(dossier, 'instructeur', 'Élevages indemnisés', 2)
    ecrit?(0, "Catégorie d'animaux", poules)
    ecrit?(0, 'Animaux déclarés non bio', '50')
    ecrit?(0, 'Animaux déclarés bio', '5')
    ecrit?(1, "Catégorie d'animaux", 'Bovins reproducteurs')
    ecrit?(1, 'Animaux déclarés bio', '0')
  end

  it 'never writes the animals kept by the instructor' do
    ids = rows.flat_map(&:champs).select { described_class::RETENUS.include?(it.label) }.map(&:id)
    expect(SetAnnotationValue).not_to have_received(:raw_set_value).with(anything, anything, satisfy { ids.include?(it) }, anything)
  end
end
