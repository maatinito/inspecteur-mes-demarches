# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FieldChecker do
  describe '#object_field_values with ReferentielDePolynesie' do
    let(:checker) { FieldChecker.new({}) }
    let(:dossier) { instance_double('Dossier', number: 123) }

    before do
      checker.instance_variable_set(:@dossier, dossier)
    end

    context 'when accessing ReferentielDePolynesie columns' do
      let(:referentiel_champ) do
        double('ReferentielDePolynesieChamp',
               __typename: 'ReferentielDePolynesieChamp',
               string_value: 'ICPE-001',
               columns: [
                 double(name: 'section', value: 'A'),
                 double(name: 'rubrique', value: '2510'),
                 double(name: 'alinea', value: '1')
               ])
      end

      it 'returns column value when accessing existing column' do
        result = checker.object_field_values(referentiel_champ, 'section')
        expect(result).to eq(['A'])
      end

      it 'returns empty array when accessing non-existent column' do
        result = checker.object_field_values(referentiel_champ, 'inexistant')
        expect(result).to eq([])
      end

      it 'handles nested access with columns' do
        dossier_with_champ = double('Dossier',
                                    champs: [referentiel_champ])
        allow(referentiel_champ).to receive(:label).and_return('ICPE')

        # Mock select_champ to return the referentiel when searching for 'ICPE'
        allow(checker).to receive(:select_champ).with([referentiel_champ], 'ICPE').and_return([referentiel_champ])
        allow(checker).to receive(:select_champ).with(anything, 'section').and_return([])

        result = checker.object_field_values(dossier_with_champ, 'ICPE.section')
        expect(result).to eq(['A'])
      end
    end

    context 'when not a ReferentielDePolynesie' do
      let(:regular_champ) do
        double('TextChamp',
               __typename: 'TextChamp',
               value: 'Some text')
      end

      it 'does not try to access columns' do
        result = checker.object_field_values(regular_champ, 'section')
        expect(result).to eq([])
      end
    end
  end

  describe '#convert_column_value' do
    let(:checker) { FieldChecker.new({}) }

    context 'with boolean values' do
      it 'converts "true" to boolean true' do
        expect(checker.convert_column_value('true')).to be true
        expect(checker.convert_column_value('True')).to be true
      end

      it 'converts "vrai" to boolean true' do
        expect(checker.convert_column_value('vrai')).to be true
        expect(checker.convert_column_value('Vrai')).to be true
      end

      it 'converts "false" to boolean false' do
        expect(checker.convert_column_value('false')).to be false
        expect(checker.convert_column_value('False')).to be false
      end

      it 'converts "faux" to boolean false' do
        expect(checker.convert_column_value('faux')).to be false
        expect(checker.convert_column_value('Faux')).to be false
      end
    end

    context 'with date values' do
      it 'parses French format dates with slashes' do
        result = checker.convert_column_value('15/01/2024')
        expect(result).to be_a(Date)
        expect(result.day).to eq(15)
        expect(result.month).to eq(1)
        expect(result.year).to eq(2024)
      end

      it 'parses ISO format dates' do
        result = checker.convert_column_value('2024-01-15')
        expect(result).to be_a(Date)
        expect(result.day).to eq(15)
        expect(result.month).to eq(1)
        expect(result.year).to eq(2024)
      end

      it 'parses dates with dots' do
        result = checker.convert_column_value('15.01.2024')
        expect(result).to be_a(Date)
        expect(result.day).to eq(15)
        expect(result.month).to eq(1)
        expect(result.year).to eq(2024)
      end

      it 'does not parse invalid dates' do
        result = checker.convert_column_value('32/13/2024')
        expect(result).to eq('32/13/2024')
      end
    end

    context 'with numeric values' do
      it 'converts integer strings to integers' do
        expect(checker.convert_column_value('42')).to eq(42)
        expect(checker.convert_column_value('-42')).to eq(-42)
      end

      it 'converts decimal strings to floats' do
        expect(checker.convert_column_value('42.5')).to eq(42.5)
        expect(checker.convert_column_value('-42.5')).to eq(-42.5)
      end

      it 'does not convert numbers with text' do
        expect(checker.convert_column_value('42abc')).to eq('42abc')
        expect(checker.convert_column_value('abc42')).to eq('abc42')
      end
    end

    context 'with string values' do
      it 'returns regular strings as-is' do
        expect(checker.convert_column_value('Hello World')).to eq('Hello World')
        expect(checker.convert_column_value('Section A')).to eq('Section A')
      end
    end

    context 'with nil or empty values' do
      it 'returns nil for nil input' do
        expect(checker.convert_column_value(nil)).to be_nil
      end

      it 'returns nil for empty string' do
        expect(checker.convert_column_value('')).to be_nil
      end
    end
  end

  describe '#referentiel_de_polynesie?' do
    let(:checker) { FieldChecker.new({}) }

    it 'returns true for ReferentielDePolynesieChamp' do
      champ = double('Champ', __typename: 'ReferentielDePolynesieChamp')
      expect(checker.referentiel_de_polynesie?(champ)).to be true
    end

    it 'returns false for other champ types' do
      champ = double('Champ', __typename: 'TextChamp')
      expect(checker.referentiel_de_polynesie?(champ)).to be false
    end

    it 'returns false for objects without __typename' do
      champ = double('Object')
      expect(checker.referentiel_de_polynesie?(champ)).to be false
    end
  end
end
