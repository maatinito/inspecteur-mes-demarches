# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Catanat::CulturesSinistrees do
  let(:controle) do
    described_class.new(champ: 'Culture sinistrée', bloc_indemnisation: 'Cultures indemnisées', bloc_plafond: 'Plafond par famille')
  end
  let(:demarche) { double('Demarche', instructeur: 'instructeur') }

  def column(name, value)
    double('Column', id: Base64.encode64("Column-type_de_champ/200274-$.referentiel.data.row.#{name}"), string_value: value)
  end

  def culture(nom, famille, surface, bio: false)
    double('Row', champs: [
             double('Champ', label: 'Culture', __typename: 'DropDownListChamp', string_value: nom,
                             columns: [column('culture', nom), column('famille', famille)]),
             double('Champ', label: 'Culture bio ?', __typename: 'YesNoChamp', checked: bio),
             double('Champ', label: 'Surface détruite (m²)', __typename: 'IntegerNumberChamp', int_value: surface)
           ])
  end

  def ligne(labels, valeurs: {}, entiers: [])
    double('Row', champs: labels.map do |label|
      attributs = entiers.include?(label) ? { int_value: valeurs[label] } : { value: valeurs[label] }
      double('Champ', id: SecureRandom.hex(4), label:, __typename: entiers.include?(label) ? 'IntegerNumberChamp' : 'TextChamp', **attributs)
    end)
  end

  let(:maraichage) { 'Cultures maraîchères et horticoles' }
  let(:source) do
    double('Bloc', label: 'Culture sinistrée', __typename: 'RepetitionChamp', rows: [
             culture('tomate', maraichage, 300),
             culture('salade', maraichage, 200),
             culture('vanille', 'Vanille', 100),
             culture('poireau', maraichage, 50, bio: true)
           ])
  end
  let(:colonnes) { [*described_class::COLONNES, described_class::RETENUS.first, described_class::MONTANT] }
  let(:indemnisation) do
    double('Bloc', label: 'Cultures indemnisées', rows: [
             ligne(colonnes, valeurs: { 'Famille de cultures' => maraichage, 'Bio / non bio' => 'Non bio',
                                        described_class::MONTANT => '10000.0' }, entiers: [described_class::RETENUS.first]),
             ligne(colonnes, valeurs: { 'Famille de cultures' => maraichage, 'Bio / non bio' => 'Bio',
                                        described_class::MONTANT => '1300.0' }, entiers: [described_class::RETENUS.first]),
             ligne(colonnes, entiers: [described_class::RETENUS.first])
           ])
  end
  let(:plafond) do
    double('Bloc', label: 'Plafond par famille', rows: Array.new(2) { ligne(described_class::PLAFOND, entiers: ['Montant théorique total (F)']) })
  end
  let(:dossier) do
    double('Dossier', id: 'D1', number: 1, state: 'en_construction', champs: [source], annotations: [indemnisation, plafond])
  end

  before do
    allow(SetAnnotationValue).to receive(:allocate_blocks) { |_d, _i, label, _n| dossier.annotations.find { it.label == label } }
    allow(SetAnnotationValue).to receive(:raw_set_value)
    allow(SetAnnotationValue).to receive(:set_value).and_return(true)
    controle.process(demarche, dossier)
  end

  def ecrit?(bloc, ligne, label, valeur)
    champ = bloc.rows[ligne].champs.find { it.label == label }
    expect(SetAnnotationValue).to have_received(:raw_set_value).with('D1', 'instructeur', champ.id, valeur)
  end

  it 'groups the cultures by family and mode, in order of appearance' do
    expect(SetAnnotationValue).to have_received(:allocate_blocks).with(dossier, 'instructeur', 'Cultures indemnisées', 3)
    ecrit?(indemnisation, 0, 'Cultures', 'tomate, salade')
    ecrit?(indemnisation, 0, 'm² déclarés', '500')
    ecrit?(indemnisation, 1, 'Famille de cultures', 'Vanille')
    ecrit?(indemnisation, 1, 'Bio / non bio', 'Non bio')
    ecrit?(indemnisation, 2, 'Famille de cultures', maraichage)
    ecrit?(indemnisation, 2, 'Bio / non bio', 'Bio')
    ecrit?(indemnisation, 2, 'm² déclarés', '50')
  end

  it 'maps a family spelled differently to the option of the list' do
    controle.params[:familles] = ['Bananiers/fei', maraichage]
    expect(controle.send(:option_equivalente, "Bananiers/fe'i", controle.params[:familles])).to eq('Bananiers/fei')
    expect(controle.send(:option_equivalente, 'Inconnue', controle.params[:familles])).to eq('Inconnue')
  end

  it 'warns and leaves the family empty when the referentiel column cannot be found' do
    allow(Rails.logger).to receive(:warn)
    champ = double('Champ', string_value: 'tomate', columns: [double('Column', id: Base64.encode64('autre-format'), string_value: maraichage)])
    expect(controle.send(:famille, champ)).to eq('')
    expect(Rails.logger).to have_received(:warn).with(/colonne « famille » introuvable/)
  end

  it 'never writes the surfaces kept by the instructor' do
    ids = indemnisation.rows.flat_map(&:champs).select { it.label == described_class::RETENUS.first }.map(&:id)
    expect(SetAnnotationValue).not_to have_received(:raw_set_value).with(anything, anything, satisfy { ids.include?(it) }, anything)
  end

  it 'totals the computed amounts per family, bio and non bio together' do
    ecrit?(plafond, 0, 'Famille (récapitulatif)', maraichage)
    ecrit?(plafond, 0, 'Montant théorique total (F)', 11_300)
    ecrit?(plafond, 1, 'Famille (récapitulatif)', 'Vanille')
    ecrit?(plafond, 1, 'Montant théorique total (F)', 0)
    expect(controle.dossier_updated?).to be true
  end

  it 'writes the total damaged surface, bio included, when champ_surfaces is set' do
    expect(SetAnnotationValue).not_to have_received(:set_value)
    controle.params[:champ_surfaces] = 'Surfaces endommagées'
    controle.process(demarche, dossier)
    expect(SetAnnotationValue).to have_received(:set_value)
      .with(dossier, 'instructeur', 'Surfaces endommagées', '650 m² dont 50 m² en bio')
  end
end
