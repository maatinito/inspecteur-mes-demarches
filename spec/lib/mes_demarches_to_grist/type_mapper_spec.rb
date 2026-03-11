# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MesDemarchesToGrist::TypeMapper do
  let(:mapper) { described_class.new }

  describe '.supported_type?' do
    it 'returns true for supported types' do
      expect(described_class.supported_type?('TextChampDescriptor')).to be true
      expect(described_class.supported_type?('IntegerNumberChampDescriptor')).to be true
      expect(described_class.supported_type?('CheckboxChampDescriptor')).to be true
      expect(described_class.supported_type?('DropDownListChampDescriptor')).to be true
      expect(described_class.supported_type?('PieceJustificativeChampDescriptor')).to be true
    end

    it 'returns false for unsupported types' do
      expect(described_class.supported_type?('RepetitionChampDescriptor')).to be false
      expect(described_class.supported_type?('SiretChampDescriptor')).to be false
    end
  end

  describe '.should_ignore_type?' do
    it 'returns true for ignored types' do
      expect(described_class.should_ignore_type?('ExplicationChampDescriptor')).to be true
      expect(described_class.should_ignore_type?('HeaderSectionChampDescriptor')).to be true
    end

    it 'returns false for non-ignored types' do
      expect(described_class.should_ignore_type?('TextChampDescriptor')).to be false
    end
  end

  describe '#map_field_type' do
    it 'maps Text to Text' do
      result = mapper.map_field_type('TextChampDescriptor')
      expect(result[:type]).to eq('Text')
    end

    it 'maps IntegerNumber to Integer' do
      result = mapper.map_field_type('IntegerNumberChampDescriptor')
      expect(result[:type]).to eq('Integer')
    end

    it 'maps DecimalNumber to Numeric' do
      result = mapper.map_field_type('DecimalNumberChampDescriptor')
      expect(result[:type]).to eq('Numeric')
    end

    it 'maps Checkbox to Bool' do
      result = mapper.map_field_type('CheckboxChampDescriptor')
      expect(result[:type]).to eq('Bool')
    end

    it 'maps Date to Date' do
      result = mapper.map_field_type('DateChampDescriptor')
      expect(result[:type]).to eq('Date')
    end

    it 'maps Datetime to DateTime:UTC' do
      result = mapper.map_field_type('DatetimeChampDescriptor')
      expect(result[:type]).to eq('DateTime:UTC')
    end

    it 'maps DropDownList to Choice with widgetOptions' do
      descriptor = { 'options' => %w[Option1 Option2] }
      result = mapper.map_field_type('DropDownListChampDescriptor', descriptor)
      expect(result[:type]).to eq('Choice')
      expect(result[:config][:widgetOptions][:choices]).to eq(%w[Option1 Option2])
    end

    it 'maps DropDownList with otherOption to Text' do
      descriptor = { 'otherOption' => true }
      result = mapper.map_field_type('DropDownListChampDescriptor', descriptor)
      expect(result[:type]).to eq('Text')
    end

    it 'maps MultipleDropDownList to ChoiceList' do
      descriptor = { 'options' => %w[A B C] }
      result = mapper.map_field_type('MultipleDropDownListChampDescriptor', descriptor)
      expect(result[:type]).to eq('ChoiceList')
      expect(result[:config][:widgetOptions][:choices]).to eq(%w[A B C])
    end

    it 'maps Civilite to Choice with M./Mme' do
      result = mapper.map_field_type('CiviliteChampDescriptor')
      expect(result[:type]).to eq('Choice')
      expect(result[:config][:widgetOptions][:choices]).to eq(%w[M. Mme])
    end

    it 'maps PieceJustificative to Attachments' do
      result = mapper.map_field_type('PieceJustificativeChampDescriptor')
      expect(result[:type]).to eq('Attachments')
    end

    it 'raises for unsupported types' do
      expect { mapper.map_field_type('SiretChampDescriptor') }
        .to raise_error(described_class::UnsupportedTypeError)
    end
  end

  describe '#generate_field_name' do
    it 'returns the label cleaned' do
      expect(mapper.generate_field_name('  Nom du champ  ')).to eq('Nom du champ')
    end

    it 'adds prefix when provided' do
      expect(mapper.generate_field_name('Champ', 'Annot')).to eq('Annot - Champ')
    end
  end
end
