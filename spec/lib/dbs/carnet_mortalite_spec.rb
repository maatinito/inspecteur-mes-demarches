# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dbs::CarnetMortalite do
  let(:recu) { 1000 }

  it 'calcule le restant de la veille en ignorant les jours non saisis' do
    expect(described_class.restant_veille(recu, [5, nil, 10], 3)).to eq 995
  end

  it 'alerte au seuil, égalité comprise, sur la base du restant de la veille' do
    morts = [10, 29, 30] # J3 : restant veille 961, 3 % = 28,83 → 30 alerte ; J2 : restant 990, 29,7 → 29 non
    expect(described_class.jours_en_alerte(recu, morts, 0.03)).to eq [3]
    expect(described_class.jours_en_alerte(100, [3], 0.03)).to eq [1]
  end

  it 'ne divise pas par zéro quand tout le lot est mort' do
    expect(described_class.jours_en_alerte(10, [10, 0], 0.03)).to eq [1]
    expect(described_class.mortalite_fenetre(10, [10, 0], 3)).to eq 100.0
  end

  it 'compte un jour à 0 mort comme une saisie, et saute les trous' do
    expect(described_class.dernier_jour_saisi([1, nil, 0])).to eq 3
    expect(described_class.dernier_jour_saisi([nil, nil])).to eq 0
  end

  it 'calcule la mortalité des 3 derniers jours saisis' do
    morts = [0, 0, 5, 5, 10] # fenêtre J3-J5 = 20 ; restant avant J3 = 1000
    expect(described_class.mortalite_fenetre(recu, morts, 3)).to eq 2.0
    expect(described_class.mortalite_fenetre(recu, [], 3)).to eq 0.0
  end
end
