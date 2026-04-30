# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MesDemarchesToGrist::DataExtractor do
  let(:field_metadata) do
    {
      'Nom' => { type: 'Text', id: 'Nom', isFormula: false },
      'Age' => { type: 'Integer', id: 'Age', isFormula: false },
      'Montant' => { type: 'Numeric', id: 'Montant', isFormula: false },
      'Date naissance' => { type: 'Date', id: 'Date_naissance', isFormula: false },
      'Actif' => { type: 'Bool', id: 'Actif', isFormula: false },
      'Catégorie' => { type: 'Choice', id: 'Categorie', isFormula: false },
      'Tags' => { type: 'ChoiceList', id: 'Tags', isFormula: false }
    }
  end

  let(:extractor) { described_class.new(field_metadata) }

  describe '#format_date_epoch' do
    it 'converts ISO date to epoch seconds' do
      result = extractor.send(:format_date_epoch, '2025-06-15')
      expect(result).to eq(Date.parse('2025-06-15').to_time.to_i)
    end

    it 'returns nil for blank dates' do
      expect(extractor.send(:format_date_epoch, nil)).to be_nil
      expect(extractor.send(:format_date_epoch, '')).to be_nil
    end

    it 'returns nil for invalid dates' do
      expect(extractor.send(:format_date_epoch, 'not-a-date')).to be_nil
    end
  end

  describe '#format_datetime_epoch' do
    it 'converts ISO datetime to epoch seconds' do
      result = extractor.send(:format_datetime_epoch, '2025-06-15T10:30:00+00:00')
      expect(result).to eq(DateTime.parse('2025-06-15T10:30:00+00:00').to_time.to_i)
    end

    it 'returns nil for blank datetimes' do
      expect(extractor.send(:format_datetime_epoch, nil)).to be_nil
    end
  end

  describe '#normalize_boolean' do
    it 'returns true for oui' do
      expect(extractor.send(:normalize_boolean, 'oui')).to be true
    end

    it 'returns true for true' do
      expect(extractor.send(:normalize_boolean, 'true')).to be true
    end

    it 'returns false for non' do
      expect(extractor.send(:normalize_boolean, 'non')).to be false
    end

    it 'returns nil for blank' do
      expect(extractor.send(:normalize_boolean, nil)).to be_nil
    end
  end

  describe '#normalize_choice_list' do
    it 'returns Grist L-encoded array' do
      champ = double('champ', values: %w[tag1 tag2])
      result = extractor.send(:normalize_choice_list, champ)
      expect(result).to eq(%w[L tag1 tag2])
    end

    it 'returns ["L"] for blank values' do
      champ = double('champ', values: nil)
      result = extractor.send(:normalize_choice_list, champ)
      expect(result).to eq(['L'])
    end
  end

  describe '#normalize_integer' do
    it 'converts string to integer' do
      champ = double('champ', __typename: 'IntegerNumberChamp', value: '42')
      allow(champ).to receive(:respond_to?).with(:value).and_return(true)
      result = extractor.send(:normalize_integer, champ)
      expect(result).to eq(42)
    end

    it 'returns nil for blank' do
      champ = double('champ', __typename: 'IntegerNumberChamp', value: '')
      allow(champ).to receive(:respond_to?).with(:value).and_return(true)
      result = extractor.send(:normalize_integer, champ)
      expect(result).to be_nil
    end
  end

  describe '#normalize_numeric' do
    it 'converts string to float' do
      champ = double('champ', __typename: 'DecimalNumberChamp', value: '3.14')
      allow(champ).to receive(:respond_to?).with(:value).and_return(true)
      result = extractor.send(:normalize_numeric, champ)
      expect(result).to eq(3.14)
    end
  end
end
