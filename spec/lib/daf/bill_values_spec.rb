# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Daf::BillValues do
  # Régression : les montants sont des IntegerNumberChamp dont `value` est aliasé
  # en `intValue` (commit 0ad4ea8). L'appeler directement levait
  # « unfetched field `value' ». On lit via champ_value (dispatch __typename).
  let(:controle) { Daf::BillValues.new({}) }

  def numeric_champ(int)
    champ = double('IntegerNumberChamp', __typename: 'IntegerNumberChamp', int_value: int)
    allow(champ).to receive(:value).and_raise("unfetched field `value'")
    champ
  end

  before do
    values = {
      'Montant transcription' => numeric_champ(500),
      'Complément transcription' => numeric_champ(100),
      'Montant inscription' => numeric_champ(300),
      'Complément inscription' => numeric_champ(0)
    }
    allow(controle).to receive(:annotation) { |label| values[label] }
  end

  it 'additionne les montants numériques sans lever et calcule le total' do
    output = {}
    expect { controle.process_row(nil, output) }.not_to raise_error
    expect(output['Transcription']).to eq(600)
    expect(output['Inscription']).to eq(300)
    expect(output['Total']).to eq(900)
  end
end
