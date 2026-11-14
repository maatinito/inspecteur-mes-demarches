# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReferentielTable do
  let(:attributs) { { backend: 'baserow', table_ref: '42', mode: 'archive' } }

  it 'est valide avec backend, table et mode' do
    expect(described_class.new(attributs)).to be_valid
  end

  it 'refuse un mode inconnu' do
    expect(described_class.new(attributs.merge(mode: 'autre'))).not_to be_valid
  end

  it 'refuse une table sans backend' do
    expect(described_class.new(attributs.merge(backend: nil))).not_to be_valid
  end

  it 'refuse deux fois la même table pour un backend' do
    described_class.create!(attributs)
    expect(described_class.new(attributs)).not_to be_valid
  end

  it 'accepte la même référence sur un autre backend' do
    described_class.create!(attributs)
    expect(described_class.new(attributs.merge(backend: 'grist'))).to be_valid
  end

  it 'dlnuf? vaut vrai seulement en mode dlnuf' do
    expect(described_class.new(attributs.merge(mode: 'dlnuf')).dlnuf?).to be(true)
    expect(described_class.new(attributs).dlnuf?).to be(false)
  end
end
