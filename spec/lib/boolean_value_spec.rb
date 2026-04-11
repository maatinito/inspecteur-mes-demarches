# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BooleanValue do
  describe '#to_s' do
    it 'renvoie "Oui" pour true' do
      expect(described_class.new(true).to_s).to eq('Oui')
    end

    it 'renvoie "Non" pour false' do
      expect(described_class.new(false).to_s).to eq('Non')
    end

    it 'convertit les valeurs non booléennes en vrai/faux' do
      expect(described_class.new('anything').to_s).to eq('Oui')
      expect(described_class.new(nil).to_s).to eq('Non')
    end
  end

  describe '#texte' do
    it 'est un alias de to_s' do
      expect(described_class.new(true).texte).to eq('Oui')
      expect(described_class.new(false).texte).to eq('Non')
    end
  end

  describe '#present?' do
    it 'est vrai uniquement si la valeur est vraie' do
      expect(described_class.new(true).present?).to be true
      expect(described_class.new(false).present?).to be false
    end
  end

  describe '#empty? / #vide?' do
    it 'est vrai uniquement si la valeur est fausse' do
      expect(described_class.new(false).empty?).to be true
      expect(described_class.new(true).empty?).to be false
      expect(described_class.new(false).vide?).to be true
    end
  end

  describe '#true? / #false?' do
    it 'true? correspond à la valeur' do
      expect(described_class.new(true).true?).to be true
      expect(described_class.new(false).true?).to be false
    end

    it 'false? est la négation' do
      expect(described_class.new(false).false?).to be true
      expect(described_class.new(true).false?).to be false
    end

    it 'fournit des alias français' do
      expect(described_class.new(true).vrai?).to be true
      expect(described_class.new(false).faux?).to be true
    end
  end

  describe '#==' do
    it 'compare avec un autre BooleanValue' do
      expect(described_class.new(true)).to eq(described_class.new(true))
      expect(described_class.new(false)).to eq(described_class.new(false))
      expect(described_class.new(true)).not_to eq(described_class.new(false))
    end

    it 'compare avec un booléen natif' do
      expect(described_class.new(true)).to eq(true)
      expect(described_class.new(false)).to eq(false)
    end

    it 'renvoie false face à un autre type' do
      expect(described_class.new(true) == 'Oui').to be false
    end
  end

  describe '#to_bool' do
    it 'renvoie le booléen natif' do
      expect(described_class.new(true).to_bool).to be true
      expect(described_class.new(false).to_bool).to be false
    end
  end
end
