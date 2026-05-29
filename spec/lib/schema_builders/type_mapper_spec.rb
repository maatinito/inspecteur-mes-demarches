# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchemaBuilders::TypeMapper do
  describe '.for(:baserow)' do
    let(:mapper) { described_class.for(:baserow) }

    it 'retourne un mapper configuré pour Baserow' do
      expect(mapper.target).to eq(:baserow)
    end

    describe '#call' do
      it 'mappe TextChampDescriptor sur text' do
        expect(mapper.call('TextChampDescriptor')).to eq('text')
      end

      it 'mappe TextareaChampDescriptor sur long_text' do
        expect(mapper.call('TextareaChampDescriptor')).to eq('long_text')
      end

      it 'mappe IntegerNumberChampDescriptor sur number' do
        expect(mapper.call('IntegerNumberChampDescriptor')).to eq('number')
      end

      it 'mappe DateChampDescriptor sur date' do
        expect(mapper.call('DateChampDescriptor')).to eq('date')
      end

      it 'mappe CheckboxChampDescriptor sur boolean' do
        expect(mapper.call('CheckboxChampDescriptor')).to eq('boolean')
      end

      it 'mappe PieceJustificativeChampDescriptor sur file' do
        expect(mapper.call('PieceJustificativeChampDescriptor')).to eq('file')
      end

      it 'lève UnsupportedTypeError pour un type inconnu' do
        expect { mapper.call('UnknownTypeXyz') }
          .to raise_error(SchemaBuilders::TypeMapper::UnsupportedTypeError)
      end
    end

    describe '#map_field_type' do
      it 'préserve la config decimal_places pour Integer' do
        result = mapper.map_field_type('IntegerNumberChampDescriptor')
        expect(result).to eq(type: 'number', config: { number_decimal_places: 0 })
      end

      it 'préserve la config decimal_places pour Decimal' do
        result = mapper.map_field_type('DecimalNumberChampDescriptor')
        expect(result[:config][:number_decimal_places]).to eq(2)
      end

      it 'construit les select_options pour MultipleDropDownList' do
        result = mapper.map_field_type(
          'MultipleDropDownListChampDescriptor',
          { 'options' => %w[A B C] }
        )
        expect(result[:type]).to eq('multiple_select')
        expect(result[:config][:select_options]).to be_an(Array)
        expect(result[:config][:select_options].size).to eq(3)
        expect(result[:config][:select_options].first).to eq(value: 'A', color: 'blue')
      end

      it 'bascule vers text si DropDownList a otherOption=true' do
        result = mapper.map_field_type(
          'DropDownListChampDescriptor',
          { 'otherOption' => true, 'options' => ['A'] }
        )
        expect(result).to eq(type: 'text', config: {})
      end

      it 'génère les select_options Civilité (M./Mme)' do
        result = mapper.map_field_type('CiviliteChampDescriptor')
        expect(result[:type]).to eq('single_select')
        expect(result[:config][:select_options]).to eq([
                                                         { value: 'M.', color: 'blue' },
                                                         { value: 'Mme', color: 'purple' }
                                                       ])
      end
    end
  end

  describe '.for(:grist)' do
    let(:mapper) { described_class.for(:grist) }

    it 'retourne un mapper configuré pour Grist' do
      expect(mapper.target).to eq(:grist)
    end

    describe '#call' do
      it 'mappe TextChampDescriptor sur Text' do
        expect(mapper.call('TextChampDescriptor')).to eq('Text')
      end

      it 'mappe TextareaChampDescriptor sur Text (Grist n\'a pas de long_text)' do
        expect(mapper.call('TextareaChampDescriptor')).to eq('Text')
      end

      it 'mappe IntegerNumberChampDescriptor sur Integer' do
        expect(mapper.call('IntegerNumberChampDescriptor')).to eq('Integer')
      end

      it 'mappe DecimalNumberChampDescriptor sur Numeric' do
        expect(mapper.call('DecimalNumberChampDescriptor')).to eq('Numeric')
      end

      it 'mappe DateChampDescriptor sur Date' do
        expect(mapper.call('DateChampDescriptor')).to eq('Date')
      end

      it 'mappe DatetimeChampDescriptor sur DateTime:UTC' do
        expect(mapper.call('DatetimeChampDescriptor')).to eq('DateTime:UTC')
      end

      it 'mappe CheckboxChampDescriptor sur Bool' do
        expect(mapper.call('CheckboxChampDescriptor')).to eq('Bool')
      end

      it 'mappe PieceJustificativeChampDescriptor sur Attachments' do
        expect(mapper.call('PieceJustificativeChampDescriptor')).to eq('Attachments')
      end

      it 'lève UnsupportedTypeError pour un type inconnu' do
        expect { mapper.call('UnknownTypeXyz') }
          .to raise_error(SchemaBuilders::TypeMapper::UnsupportedTypeError)
      end
    end

    describe '#map_field_type' do
      it 'construit widgetOptions.choices pour MultipleDropDownList' do
        result = mapper.map_field_type(
          'MultipleDropDownListChampDescriptor',
          { 'options' => %w[A B C] }
        )
        expect(result[:type]).to eq('ChoiceList')
        expect(result[:config]).to eq(widgetOptions: { choices: %w[A B C] })
      end

      it 'bascule vers Text si DropDownList a otherOption=true' do
        result = mapper.map_field_type(
          'DropDownListChampDescriptor',
          { 'otherOption' => true, 'options' => ['A'] }
        )
        expect(result).to eq(type: 'Text', config: {})
      end

      it 'génère widgetOptions.choices pour Civilité' do
        result = mapper.map_field_type('CiviliteChampDescriptor')
        expect(result[:type]).to eq('Choice')
        expect(result[:config]).to eq(widgetOptions: { choices: %w[M. Mme] })
      end
    end
  end

  describe '.for(unknown target)' do
    it 'lève ArgumentError pour une cible inconnue' do
      expect { described_class.for(:notion) }
        .to raise_error(ArgumentError, /unknown target/)
    end
  end

  describe '.should_ignore_type?' do
    it 'identifie les types ignorés (sections, explications)' do
      expect(described_class.should_ignore_type?('HeaderSectionChampDescriptor')).to be true
      expect(described_class.should_ignore_type?('ExplicationChampDescriptor')).to be true
    end

    it 'retourne false pour les types non ignorés' do
      expect(described_class.should_ignore_type?('TextChampDescriptor')).to be false
    end
  end

  describe '#supported_type?' do
    it 'reconnaît les types supportés par Baserow' do
      mapper = described_class.for(:baserow)
      expect(mapper.supported_type?('TextChampDescriptor')).to be true
      expect(mapper.supported_type?('RepetitionChampDescriptor')).to be false
    end

    it 'reconnaît les types supportés par Grist' do
      mapper = described_class.for(:grist)
      expect(mapper.supported_type?('TextChampDescriptor')).to be true
      expect(mapper.supported_type?('SiretChampDescriptor')).to be false
    end
  end

  describe '#generate_field_name' do
    let(:mapper) { described_class.for(:baserow) }

    it 'normalise les espaces multiples' do
      expect(mapper.generate_field_name('Test  avec    espaces')).to eq('Test avec espaces')
    end

    it 'ajoute un préfixe quand fourni' do
      expect(mapper.generate_field_name('Email', 'annotation')).to eq('annotation - Email')
    end
  end
end
