# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
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

    it 'préserve false (une case décochée doit repasser à false dans Grist)' do
      expect(extractor.send(:normalize_boolean, false)).to be(false)
      expect(extractor.send(:normalize_boolean, true)).to be(true)
    end
  end

  describe '#extract_fields' do
    let(:field_metadata) do
      {
        'Notes' => { type: 'Text', id: 'Notes', isFormula: false },
        'Programme' => { type: 'Choice', id: 'Programme', isFormula: false },
        'Section' => { type: 'Text', id: 'Section', isFormula: false },
        'Casse' => { type: 'Text', id: 'Casse', isFormula: false },
        'Identité' => { type: 'Attachments', id: 'Identite', isFormula: false },
        'PJ' => { type: 'Attachments', id: 'PJ', isFormula: false }
      }
    end

    it 'conserve les valeurs nil pour permettre la réinitialisation de la cellule Grist' do
      champ = double('TextChamp', __typename: 'TextChamp', label: 'Notes', value: nil)

      data = extractor.send(:extract_fields, [champ])

      expect(data).to have_key('Notes')
      expect(data['Notes']).to be_nil
    end

    it 'convertit un Choice vide en nil (réinitialisation de la cellule)' do
      champ = double('TextChamp', __typename: 'TextChamp', label: 'Programme', value: '')

      data = extractor.send(:extract_fields, [champ])

      expect(data).to have_key('Programme')
      expect(data['Programme']).to be_nil
    end

    it "n'ajoute pas un champ Attachments vide (on ne touche pas aux PJ existantes)" do
      champ = double('PieceJustificativeChamp', __typename: 'PieceJustificativeChamp', label: 'PJ', files: [])

      data = extractor.send(:extract_fields, [champ])

      expect(data).not_to have_key('PJ')
    end

    it 'ignore les champs décoratifs (leur nil ne doit pas vider une cellule homonyme)' do
      champ = double('HeaderSectionChamp', __typename: 'HeaderSectionChamp', label: 'Section')

      data = extractor.send(:extract_fields, [champ])

      expect(data).not_to have_key('Section')
    end

    it 'ignore TitreIdentiteChamp (confidentialité, comme côté Baserow)' do
      champ = double('TitreIdentiteChamp', __typename: 'TitreIdentiteChamp', label: 'Identité')

      data = extractor.send(:extract_fields, [champ])

      expect(data).not_to have_key('Identité')
    end

    it 'laisse la cellule intacte quand la lecture du champ échoue (pas de vidage sur erreur)' do
      champ = double('TextChamp', __typename: 'TextChamp', label: 'Casse')
      allow(champ).to receive(:value).and_raise(GraphQL::Client::UnfetchedFieldError, 'unfetched field')
      allow(Rails.logger).to receive(:warn)

      data = extractor.send(:extract_fields, [champ])

      expect(data).not_to have_key('Casse')
      expect(Rails.logger).to have_received(:warn).with(/Casse/)
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
      champ = double('champ', __typename: 'IntegerNumberChamp', int_value: '42')
      result = extractor.send(:normalize_integer, champ)
      expect(result).to eq(42)
    end

    it 'returns nil for blank' do
      champ = double('champ', __typename: 'IntegerNumberChamp', int_value: '')
      result = extractor.send(:normalize_integer, champ)
      expect(result).to be_nil
    end
  end

  describe '#normalize_numeric' do
    it 'converts string to float' do
      champ = double('champ', __typename: 'DecimalNumberChamp', decimal_value: '3.14')
      result = extractor.send(:normalize_numeric, champ)
      expect(result).to eq(3.14)
    end
  end
end
# rubocop:enable Metrics/BlockLength
