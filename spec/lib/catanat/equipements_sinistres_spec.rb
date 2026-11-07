# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Catanat::EquipementsSinistres do
  let(:controle) do
    described_class.new(bloc_destination: 'Équipements et bâtiments indemnisés',
                        champs_source: { 'Moyen matériel endommagé': '{Matériel agricole}{ (;Référence et caractéristique;)}',
                                         'Bâtiment ou structure endommagé': '{Type de bâtiments}' })
  end
  let(:demarche) { double('Demarche', instructeur: 'instructeur') }
  let(:montant) { 'Montant du devis / facture de réparation ou remplacement (F)' }
  let(:serres) { 'Serres films plastique et ombrières' }
  let(:irrigation) { "Matériels d'irrigation" }

  def element(categorie, montant_devis, **textes)
    double('Row', champs: [
             double('Champ', label: 'Catégorie', __typename: 'DropDownListChamp', string_value: categorie, value: categorie),
             *textes.map { |label, value| double('Champ', label: label.to_s, __typename: 'TextChamp', value:) },
             double('Champ', label: montant, __typename: 'IntegerNumberChamp', int_value: montant_devis)
           ])
  end

  let(:materiels) do
    double('Bloc', label: 'Moyen matériel endommagé', __typename: 'RepetitionChamp', rows: [
             element(irrigation, 100_000, 'Matériel agricole': 'pompe', 'Référence et caractéristique': 'P2'),
             element(irrigation, 50_000, 'Matériel agricole': 'tuyaux', 'Référence et caractéristique': nil)
           ])
  end
  let(:batiments) do
    double('Bloc', label: 'Bâtiment ou structure endommagé', __typename: 'RepetitionChamp', rows: [
             element(serres, 800_000, 'Type de bâtiments': 'serre tunnel')
           ])
  end
  let(:rows) do
    Array.new(3) do
      double('Row', champs: [*described_class::COLONNES, described_class::RETENUS.first].map do |label|
        double('Champ', id: SecureRandom.hex(4), label:, __typename: label == described_class::RETENUS.first ? 'IntegerNumberChamp' : 'TextChamp',
                        value: nil, int_value: nil)
      end)
    end
  end
  let(:bloc) { double('Bloc', label: 'Équipements et bâtiments indemnisés', rows:) }
  let(:dossier) do
    double('Dossier', id: 'D1', number: 1, state: 'en_construction', champs: [materiels, batiments], annotations: [bloc])
  end

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

  it 'writes one row per category with the elements and the sum of the quotes' do
    expect(SetAnnotationValue).to have_received(:allocate_blocks).with(dossier, 'instructeur', 'Équipements et bâtiments indemnisés', 2)
    ecrit?(0, "Catégorie d'équipement", irrigation)
    ecrit?(0, 'Éléments', "pompe (P2)\ntuyaux")
    ecrit?(0, 'Montant déclaré (F)', '150000')
    ecrit?(1, "Catégorie d'équipement", serres)
    ecrit?(1, 'Éléments', 'serre tunnel')
    ecrit?(1, 'Montant déclaré (F)', '800000')
  end

  it 'never writes the amount kept by the instructor' do
    ids = rows.flat_map(&:champs).select { it.label == described_class::RETENUS.first }.map(&:id)
    expect(SetAnnotationValue).not_to have_received(:raw_set_value).with(anything, anything, satisfy { ids.include?(it) }, anything)
  end
end
