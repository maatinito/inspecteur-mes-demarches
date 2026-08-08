# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MesDemarchesToGrist::GristRef do
  describe '.ref?' do
    it { expect(described_class.ref?('Ref:Dossiers')).to be true }
    it { expect(described_class.ref?('RefList:Dossiers')).to be false }
    it { expect(described_class.ref?('Int')).to be false }
    it { expect(described_class.ref?(nil)).to be false }
  end

  describe '.encode_key' do
    it 'encode une référence en recherche par colonne visible' do
      expect(described_class.encode_key(617_871, 'Ref:Dossiers')).to eq(['l', 617_871])
    end

    it 'laisse les autres types intacts' do
      expect(described_class.encode_key(617_871, 'Int')).to eq(617_871)
      expect(described_class.encode_key('abc', 'Text')).to eq('abc')
    end

    it 'laisse intact quand le type est inconnu' do
      expect(described_class.encode_key(617_871, nil)).to eq(617_871)
    end

    it 'ne double jamais un encodage déjà fait' do
      expect(described_class.encode_key(['l', 617_871], 'Ref:Dossiers')).to eq(['l', 617_871])
    end

    it 'encode nil comme une recherche de valeur vide plutôt que de le perdre' do
      expect(described_class.encode_key(nil, 'Ref:Dossiers')).to eq(['l', nil])
    end
  end
end
