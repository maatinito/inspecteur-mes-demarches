# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PublipostageV3 do
  let(:publipostage) { described_class.new({}) }

  describe '#champ_value' do
    it 'transforme CheckboxChamp en BooleanValue(true)' do
      champ = double('CheckboxChamp', __typename: 'CheckboxChamp', value: true)
      result = publipostage.send(:champ_value, champ)
      expect(result).to be_a(BooleanValue)
      expect(result).to eq(true)
    end

    it 'transforme CheckboxChamp non cochée en BooleanValue(false)' do
      champ = double('CheckboxChamp', __typename: 'CheckboxChamp', value: false)
      result = publipostage.send(:champ_value, champ)
      expect(result).to be_a(BooleanValue)
      expect(result).to eq(false)
    end

    it 'transforme YesNoChamp en BooleanValue' do
      champ = double('YesNoChamp', __typename: 'YesNoChamp', value: true)
      expect(publipostage.send(:champ_value, champ)).to eq(true)
    end

    it 'retourne un Array<PieceJustificativeFile> pour PieceJustificativeChamp' do
      file1 = double('File', filename: 'a.pdf')
      file2 = double('File', filename: 'b.pdf')
      champ = double('PJ', __typename: 'PieceJustificativeChamp', files: [file1, file2])
      allow(PieceJustificativeFile).to receive(:new) { |f| "wrapped-#{f.filename}" }

      result = publipostage.send(:champ_value, champ)
      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
    end

    it 'délègue les TextChamp à PublipostageV2' do
      champ = double('TextChamp', __typename: 'TextChamp', value: 'hello', label: 'x')
      expect(publipostage.send(:champ_value, champ)).to eq('hello')
    end
  end

  describe '#normalize_context' do
    it 'laisse un scalaire String intact' do
      expect(publipostage.send(:normalize_context, 'Bonjour')).to eq('Bonjour')
    end

    it 'laisse un BooleanValue intact' do
      bv = BooleanValue.new(true)
      expect(publipostage.send(:normalize_context, bv)).to equal(bv)
    end

    it 'parameterize les clés de hash (accents, espaces)' do
      input = { 'Nom du Déposant' => 'Dupont' }
      result = publipostage.send(:normalize_context, input)
      expect(result.keys).to eq(['nom_du_deposant'])
    end

    it 'wrappe une Array de scalaires dans ArrayValue' do
      result = publipostage.send(:normalize_context, %w[a b c])
      expect(result).to be_an(ArrayValue)
      expect(result.to_s).to eq('a, b, c')
    end

    it 'wrappe une Array de Hash dans ArrayValue et parameterize les clés' do
      input = [{ 'Nom' => 'Dupont' }, { 'Nom' => 'Martin' }]
      result = publipostage.send(:normalize_context, input)
      expect(result).to be_an(ArrayValue)
      expect(result.first.keys).to eq(['nom'])
      expect(result.to_a.last.keys).to eq(['nom'])
    end

    it 'ne déplie PLUS les tableaux mono-élément (régression PR 141)' do
      pjf = double('PieceJustificativeFile')
      input = { 'photos' => [pjf] }

      result = publipostage.send(:normalize_context, input)
      expect(result['photos']).to be_an(ArrayValue)
      expect(result['photos'].to_a).to eq([pjf])
    end

    it 'ne convertit PLUS ["Oui"] en true (le booléen arrive déjà comme BooleanValue)' do
      result = publipostage.send(:normalize_context, ['Oui'])
      expect(result).to be_an(ArrayValue)
      expect(result.to_s).to eq('Oui')
    end

    it 'convertit le Markdown des strings imbriquées dans une Array' do
      result = publipostage.send(:normalize_context, ['**bold**'])
      expect(result).to be_an(ArrayValue)
      first = result.to_a.first
      expect(first).to respond_to(:html_content).or respond_to(:to_s)
    end

    it 'laisse un hash avec BooleanValue passer sans le toucher' do
      input = { 'accord' => BooleanValue.new(true), 'Nom' => 'Dupont' }
      result = publipostage.send(:normalize_context, input)
      expect(result['accord']).to be_a(BooleanValue)
      expect(result['accord']).to eq(true)
      expect(result['nom']).to eq('Dupont')
    end
  end

  describe '#typed_values_of' do
    let(:dossier) { double('Dossier', number: 42, champs: [], annotations: []) }

    before do
      publipostage.instance_variable_set(:@dossier, dossier)
    end

    it 'retourne par_defaut quand le champ est blank' do
      expect(publipostage.send(:typed_values_of, dossier, nil, 'fallback')).to eq('fallback')
    end

    it 'retourne un scalaire pour un champ unique scalaire' do
      text_champ = double('TextChamp', __typename: 'TextChamp', label: 'Nom', value: 'Dupont')
      allow(dossier).to receive(:champs).and_return([text_champ])

      result = publipostage.send(:typed_values_of, dossier, 'Nom', '')
      expect(result).to eq('Dupont')
    end

    it 'retourne un BooleanValue pour un CheckboxChamp unique' do
      cb = double('CheckboxChamp', __typename: 'CheckboxChamp', label: 'Accord', value: true)
      allow(dossier).to receive(:champs).and_return([cb])

      result = publipostage.send(:typed_values_of, dossier, 'Accord', '')
      expect(result).to be_a(BooleanValue)
      expect(result).to eq(true)
    end

    it 'retourne un Array pour une liste native (MultipleDropDownListChamp)' do
      multi = double('Multi', __typename: 'MultipleDropDownListChamp', label: 'Options', values: %w[a b c])
      allow(dossier).to receive(:champs).and_return([multi])

      result = publipostage.send(:typed_values_of, dossier, 'Options', nil)
      expect(result).to eq(%w[a b c])
    end

    it 'retourne un Array quand plusieurs champs matchent le label' do
      t1 = double('T1', __typename: 'TextChamp', label: 'Tag', value: 'un')
      t2 = double('T2', __typename: 'TextChamp', label: 'Tag', value: 'deux')
      allow(dossier).to receive(:champs).and_return([t1, t2])

      result = publipostage.send(:typed_values_of, dossier, 'Tag', nil)
      expect(result).to eq(%w[un deux])
    end

    it 'retourne un scalaire humanisé pour un Hash source (ligne Excel)' do
      row = { 'Col' => 'valeur' }
      result = publipostage.send(:typed_values_of, row, 'Col', nil)
      expect(result).to eq('valeur')
    end

    it 'retourne par_defaut si aucun champ trouvé' do
      allow(dossier).to receive(:champs).and_return([])
      result = publipostage.send(:typed_values_of, dossier, 'Inconnu', 'def')
      expect(result).to eq('def')
    end
  end

  describe '#get_fields' do
    let(:dossier) do
      double('Dossier',
             number: 123,
             champs: [
               double('TextChamp', __typename: 'TextChamp', label: 'Nom', value: 'Dupont'),
               double('CheckboxChamp', __typename: 'CheckboxChamp', label: 'Accord', value: true),
               double('Multi', __typename: 'MultipleDropDownListChamp', label: 'Options', values: %w[a b])
             ],
             annotations: [])
    end

    before do
      publipostage.instance_variable_set(:@dossier, dossier)
    end

    it 'construit un hash typé avec scalaires, booléens et listes' do
      definitions = %w[Nom Accord Options]
      result = publipostage.send(:get_fields, dossier, definitions, 0)

      expect(result['Dossier']).to eq(123)
      expect(result['#index']).to eq(1)
      expect(result['Nom']).to eq('Dupont')
      expect(result['Accord']).to be_a(BooleanValue)
      expect(result['Accord']).to eq(true)
      expect(result['Options']).to eq(%w[a b])
    end
  end
end
