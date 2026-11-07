# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Catanat::SyntheseIndemnisation do
  let(:sources) do
    [{ 'bloc' => 'Élevages indemnisés', 'cle' => "Catégorie d'animaux", 'montant' => 'Montant théorique élevage (F)',
       'items' => ['Poules pondeuses et poulets de chair', 'Porcs reproducteurs'] },
     { 'bloc' => 'Équipements et bâtiments indemnisés', 'cle' => "Catégorie d'équipement", 'montant' => 'Montant retenu (F)',
       'items' => ['Serres films plastique et ombrières'] }]
  end
  let(:controle) { described_class.new(sources:) }
  let(:demarche) { double('Demarche', instructeur: 'instructeur') }

  def ligne(categorie, montant, cle: "Catégorie d'animaux", colonne: 'Montant théorique élevage (F)')
    double('Row', champs: [double('Champ', label: cle, __typename: 'TextChamp', value: categorie),
                           double('Champ', label: colonne, __typename: 'FormuleChamp', value: montant)])
  end

  def annotation(label) = double('Champ', label:, __typename: 'IntegerNumberChamp', int_value: nil)

  let(:elevages) do
    double('Bloc', label: 'Élevages indemnisés', rows: [ligne('Poules pondeuses et poulets de chair', '5300.0'),
                                                        ligne('Poules pondeuses et poulets de chair', '700'),
                                                        ligne('Lapins', '100'),
                                                        ligne(nil, nil)])
  end
  let(:annotations) do
    [elevages,
     annotation('Montant estimé – Poules pondeuses et poulets de chair (F)'),
     annotation('Montant estimé – Porcs reproducteurs (F)'),
     annotation('Montant estimé – Serres films plastique et ombrières (F)')]
  end
  let(:dossier) { double('Dossier', id: 'D1', number: 1, state: 'en_construction', annotations:) }

  before do
    allow(SetAnnotationValue).to receive(:set_value).and_return(true)
    controle.process(demarche, dossier)
  end

  it 'writes the total of each item, 0 for an item without line' do
    expect(SetAnnotationValue).to have_received(:set_value)
      .with(dossier, 'instructeur', 'Montant estimé – Poules pondeuses et poulets de chair (F)', 6000)
    expect(SetAnnotationValue).to have_received(:set_value)
      .with(dossier, 'instructeur', 'Montant estimé – Porcs reproducteurs (F)', 0)
    expect(controle.dossier_updated?).to be true
  end

  it 'skips a source whose block is hidden (absent from the API)' do
    expect(SetAnnotationValue).not_to have_received(:set_value)
      .with(anything, anything, 'Montant estimé – Serres films plastique et ombrières (F)', anything)
  end
end
