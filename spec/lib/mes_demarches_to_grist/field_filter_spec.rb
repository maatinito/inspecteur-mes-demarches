# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MesDemarchesToGrist::FieldFilter do
  let(:columns) do
    {
      'nom' => { id: 'nom', label: 'Nom', type: 'Text', isFormula: false, formula: '' },
      'total' => { id: 'total', label: 'Total', type: 'Numeric', isFormula: true, formula: '$a + $b' },
      # Colonne vide : créée dans Grist sans donnée ni formule. Grist la marque
      # isFormula=true, mais une écriture la convertit en colonne de données.
      'vide' => { id: 'vide', label: 'Vide', type: 'Text', isFormula: true, formula: '' }
    }
  end
  let(:table) { instance_double(Grist::Table, columns: columns) }

  before { allow(Grist::Config).to receive(:table).and_return(table) }

  it 'écarte les colonnes formules et les colonnes inconnues, garde les colonnes vides' do
    filtre = described_class.new('doc', 'Dossiers')

    expect(filtre.filter_syncable_fields('nom' => 'a', 'total' => 1, 'vide' => 'b', 'inconnue' => 'c'))
      .to eq('nom' => 'a', 'vide' => 'b')
  end
end
