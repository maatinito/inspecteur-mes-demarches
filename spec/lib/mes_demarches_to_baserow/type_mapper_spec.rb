# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MesDemarchesToBaserow::TypeMapper do
  let(:mapper) { described_class.new }

  describe '.supported_type?' do
    it 'returns true for supported types' do
      expect(described_class.supported_type?('TextChampDescriptor')).to be true
      expect(described_class.supported_type?('IntegerNumberChampDescriptor')).to be true
      expect(described_class.supported_type?('DateChampDescriptor')).to be true
      expect(described_class.supported_type?('CheckboxChampDescriptor')).to be true
      expect(described_class.supported_type?('PieceJustificativeChampDescriptor')).to be true
      expect(described_class.supported_type?('CiviliteChampDescriptor')).to be true
    end

    it 'returns false for unsupported types' do
      expect(described_class.supported_type?('RepetitionChampDescriptor')).to be false
      expect(described_class.supported_type?('UnknownType')).to be false
    end
  end

  describe '#map_field_type' do
    it 'maps TextChampDescriptor to text' do
      result = mapper.map_field_type('TextChampDescriptor')
      expect(result[:type]).to eq('text')
      expect(result[:config]).to eq({})
    end

    it 'maps IntegerNumberChampDescriptor to number with 0 decimals' do
      result = mapper.map_field_type('IntegerNumberChampDescriptor')
      expect(result[:type]).to eq('number')
      expect(result[:config][:number_decimal_places]).to eq(0)
    end

    it 'maps DecimalNumberChampDescriptor to number with 2 decimals' do
      result = mapper.map_field_type('DecimalNumberChampDescriptor')
      expect(result[:type]).to eq('number')
      expect(result[:config][:number_decimal_places]).to eq(2)
    end

    it 'maps DateChampDescriptor to date with EU format' do
      result = mapper.map_field_type('DateChampDescriptor')
      expect(result[:type]).to eq('date')
      expect(result[:config][:date_format]).to eq('EU')
      expect(result[:config][:date_include_time]).to be false
    end

    it 'maps CheckboxChampDescriptor to boolean' do
      result = mapper.map_field_type('CheckboxChampDescriptor')
      expect(result[:type]).to eq('boolean')
    end

    it 'maps MultipleDropDownListChampDescriptor to multiple_select' do
      field_descriptor = { 'options' => ['Option 1', 'Option 2', 'Option 3'] }
      result = mapper.map_field_type('MultipleDropDownListChampDescriptor', field_descriptor)

      expect(result[:type]).to eq('multiple_select')
      expect(result[:config][:select_options]).to be_an(Array)
      expect(result[:config][:select_options].size).to eq(3)
      expect(result[:config][:select_options].first[:value]).to eq('Option 1')
    end

    it 'maps PieceJustificativeChampDescriptor to file' do
      result = mapper.map_field_type('PieceJustificativeChampDescriptor')
      expect(result[:type]).to eq('file')
      expect(result[:config]).to eq({})
    end

    it 'maps CiviliteChampDescriptor to single_select with predefined options' do
      result = mapper.map_field_type('CiviliteChampDescriptor')
      expect(result[:type]).to eq('single_select')
      expect(result[:config][:select_options]).to be_an(Array)
      expect(result[:config][:select_options].size).to eq(2)
      expect(result[:config][:select_options].first[:value]).to eq('M.')
      expect(result[:config][:select_options].last[:value]).to eq('Mme')
      expect(result[:config][:select_options].first[:color]).to eq('blue')
      expect(result[:config][:select_options].last[:color]).to eq('purple')
    end

    it 'raises UnsupportedTypeError for unsupported types' do
      expect { mapper.map_field_type('RepetitionChampDescriptor') }
        .to raise_error(MesDemarchesToBaserow::TypeMapper::UnsupportedTypeError)
    end
  end

  describe '#generate_field_name' do
    it 'cleans field names by normalizing spaces' do
      expect(mapper.generate_field_name('Nom et Prénom')).to eq('Nom et Prénom')
      expect(mapper.generate_field_name('Adresse e-mail')).to eq('Adresse e-mail')
      expect(mapper.generate_field_name('Date de naissance')).to eq('Date de naissance')
    end

    it 'preserves accented characters' do
      expect(mapper.generate_field_name('Numéro téléphone')).to eq('Numéro téléphone')
      expect(mapper.generate_field_name('Activité professionnelle')).to eq('Activité professionnelle')
    end

    it 'adds prefix when provided' do
      expect(mapper.generate_field_name('Email', 'annotation')).to eq('annotation - Email')
      expect(mapper.generate_field_name('Commentaire', 'champ')).to eq('champ - Commentaire')
    end

    it 'normalizes multiple spaces to single space' do
      expect(mapper.generate_field_name('Test  avec    espaces')).to eq('Test avec espaces')
      expect(mapper.generate_field_name('Test@#$%^&*()')).to eq('Test@#$%^&*()')
    end
  end
end
