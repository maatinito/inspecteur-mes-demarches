# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ArrayValue do
  describe 'contrat d\'itération Sablon' do
    # Sablon::Statement::Loop#evaluate fait :
    #   value = value.to_ary if value.respond_to?(:to_ary)
    #   raise unless value.is_a?(Enumerable)
    #   value.flat_map { |item| ... }
    # Ces specs verrouillent les deux branches.

    it 'répond à to_ary' do
      expect(described_class.new([1, 2])).to respond_to(:to_ary)
    end

    it 'to_ary retourne une Array Ruby native' do
      av = described_class.new([1, 2, 3])
      expect(av.to_ary).to be_an(Array)
      expect(av.to_ary).to eq([1, 2, 3])
    end

    it 'to_ary retourne une copie défensive (ne partage pas l\'état interne)' do
      original = [1, 2, 3]
      av = described_class.new(original)
      copy = av.to_ary
      copy << 4
      expect(av.to_a).to eq([1, 2, 3])
    end

    it 'inclut Enumerable' do
      expect(described_class.ancestors).to include(Enumerable)
    end

    it 'supporte flat_map (fallback Sablon quand to_ary absent)' do
      av = described_class.new([{ nom: 'a' }, { nom: 'b' }])
      result = av.flat_map { |h| [h[:nom]] }
      expect(result).to eq(%w[a b])
    end
  end

  describe '#to_s' do
    it 'joint les éléments scalaires avec ", "' do
      expect(described_class.new(%w[a b c]).to_s).to eq('a, b, c')
    end

    it 'joint aussi des objets via leur to_s' do
      bv = BooleanValue.new(true)
      expect(described_class.new([bv, 'x']).to_s).to eq('Oui, x')
    end
  end

  describe '#present? / #empty?' do
    it 'est present? quand non vide' do
      expect(described_class.new([1]).present?).to be true
    end

    it 'est vide/empty? quand vide' do
      expect(described_class.new([]).empty?).to be true
      expect(described_class.new([]).vide?).to be true
    end
  end

  describe 'intégration réelle avec Sablon::Statement::Loop' do
    # Reproduit exactement la séquence de Sablon pour vérifier qu'un
    # ArrayValue<Hash> et un ArrayValue<Objet> passent le check sans erreur.
    def sablon_iterate(value)
      value = value.to_ary if value.respond_to?(:to_ary)
      raise 'not enumerable' unless value.is_a?(Enumerable)

      value.flat_map { |item| [item] }
    end

    it 'accepte un ArrayValue de Hash pour une boucle' do
      av = described_class.new([{ nom: 'Dupont' }, { nom: 'Martin' }])
      expect(sablon_iterate(av)).to eq([{ nom: 'Dupont' }, { nom: 'Martin' }])
    end

    it 'accepte un ArrayValue de scalaires pour une boucle' do
      av = described_class.new([1, 2, 3])
      expect(sablon_iterate(av)).to eq([1, 2, 3])
    end

    it 'accepte un ArrayValue d\'objets arbitraires pour une boucle' do
      obj1 = Object.new
      obj2 = Object.new
      av = described_class.new([obj1, obj2])
      expect(sablon_iterate(av)).to eq([obj1, obj2])
    end
  end
end
