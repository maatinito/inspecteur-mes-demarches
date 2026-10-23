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
        'PJ' => { type: 'Attachments', id: 'PJ', isFormula: false },
        'Surface' => { type: 'Int', id: 'Surface', isFormula: false }
      }
    end

    # Une démarche peut porter le même libellé sur une PJ et sur un autre champ
    # (3135 : « Extrait du cadastre » en PJ et en Oui/Non). Le champ sans fichiers
    # ne doit ni planter ni toucher la colonne de pièces jointes.
    it 'ignore un champ homonyme sans fichiers sur une colonne Attachments' do
      pj = double('PieceJustificativeChamp', __typename: 'PieceJustificativeChamp', label: 'PJ', files: [
                    double('file', filename: 'plan.pdf', byte_size: 10, url: 'https://x/plan.pdf')
                  ])
      oui_non = double('YesNoChamp', __typename: 'YesNoChamp', label: 'PJ', checked: true)

      data = extractor.send(:extract_fields, [pj, oui_non])

      expect(data['PJ']).to eq([{ url: 'https://x/plan.pdf', visible_name: 'plan.pdf' }])
    end

    it 'convertit en entier pour une colonne Int' do
      champ = double('IntegerNumberChamp', __typename: 'IntegerNumberChamp', label: 'Surface', int_value: '42')

      data = extractor.send(:extract_fields, [champ])

      expect(data['Surface']).to eq(42)
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
  # Sous-colonnes des champs composites : « <libellé> – <sous-colonne> », valeur
  # convertie selon le type de la colonne Grist (cf. ChampsComposites).
  describe 'sous-colonnes des champs composites' do
    let(:rubrique) do
      double('ReferentielDePolynesieChamp',
             __typename: 'ReferentielDePolynesieChamp', label: 'Rubrique', string_value: '2131-c',
             columns: [double(name: 'numero', value: '2131'), double(name: 'seuil', value: '12,5'),
                       double(name: 'date', value: '12/05/2024'), double(name: 'actif', value: 'vrai'),
                       double(name: 'classe', value: '2ème classe'), double(name: 'note', value: 'environ 20')])
    end
    let(:field_metadata) do
      {
        'Rubrique' => { type: 'Text' },
        'Rubrique – numero' => { type: 'Int' },
        'Rubrique – seuil' => { type: 'Numeric' },
        'Rubrique – date' => { type: 'Date' },
        'Rubrique - actif' => { type: 'Bool' },
        'Rubrique - classe' => { type: 'Text' },
        'Rubrique - note' => { type: 'Int' },
        'Rubrique - inconnue' => { type: 'Text' }
      }
    end
    let(:dossier) { double('dossier', number: 616_223, champs: [rubrique], annotations: []) }

    before do
      allow(rubrique).to receive(:value).and_return('2131-c')
      allow(extractor).to receive(:extract_system_fields).and_return({})
      allow(Rails.logger).to receive(:warn)
    end

    it 'convertit chaque sous-colonne selon le type de la colonne Grist' do
      data = extractor.send(:extract_main_table, dossier)

      expect(data).to include('Rubrique' => '2131-c', 'Rubrique – numero' => 2131, 'Rubrique – seuil' => 12.5,
                              'Rubrique – date' => Date.new(2024, 5, 12).to_time.to_i,
                              'Rubrique - actif' => true, 'Rubrique - classe' => '2ème classe')
    end

    it 'vide la cellule et journalise une valeur inconvertible' do
      data = extractor.send(:extract_main_table, dossier)

      expect(data).to have_key('Rubrique - note')
      expect(data['Rubrique - note']).to be_nil
      expect(Rails.logger).to have_received(:warn).with(/616223.*Rubrique - note.*environ 20/)
    end

    it "ne touche pas une colonne dont la sous-colonne n'existe pas" do
      expect(extractor.send(:extract_main_table, dossier)).not_to have_key('Rubrique - inconnue')
    end

    it 'remplit les sous-colonnes des lignes de bloc avec les colonnes de la table du bloc' do
      bloc = double('RepetitionChamp', __typename: 'RepetitionChamp', label: 'Rubriques',
                                       rows: [double('row', champs: [rubrique])])
      block_columns = { 'Rubrique' => { type: 'Text' }, 'Rubrique – numero' => { type: 'Int' } }
      extractor = described_class.new(field_metadata, {}, block_columns: ->(label) { block_columns if label == 'Rubriques' })

      rows = extractor.send(:extract_block_rows, double('dossier', number: 616_223), bloc)

      expect(rows.first).to include('Ligne' => 1, 'Rubrique – numero' => 2131)
    end
  end
end
# rubocop:enable Metrics/BlockLength
