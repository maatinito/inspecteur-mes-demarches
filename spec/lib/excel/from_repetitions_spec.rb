# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Excel::FromRepetitions do
  # `initialize` vérifie l'existence du modèle .xlsx sur le disque.
  let(:controle) { described_class.new(champ_cible: 'Export', modele: 'modele.xlsx') }

  before { allow(File).to receive(:exist?).with('modele.xlsx').and_return(true) }

  # RubyXL#add_cell et le YAML d'empreinte veulent une chaîne : un objet date
  # produirait une cellule typée et une empreinte de forme différente.
  it 'écrit une date de cellule sous forme de chaîne française' do
    champ = double('DateChamp', label: 'Date de début', __typename: 'DateChamp', date_value: '2026-07-27')
    expect(controle.send(:champ_cell_value, champ)).to eq('27/07/2026')
  end

  it 'laisse les autres types inchangés' do
    champ = double('TextChamp', label: 'Nom', __typename: 'TextChamp', value: 'Tavita')
    expect(controle.send(:champ_cell_value, champ)).to eq('Tavita')
  end
end
