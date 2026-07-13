# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SetAnnotationValue do
  before { Timecop.travel(Date.parse('2022/02/14')) }
  after { Timecop.return }

  def set(champ, value)
    DossierActions.on_dossier(dossier) do |d|
      SetAnnotationValue.set_value(d, demarche.instructeur, champ, value)
    end
  end

  def get(champ)
    DossierActions.on_dossier(dossier) { |d| d.annotations.select { |c| c.label == champ }.first }
  end

  def setpj(champ, path)
    DossierActions.on_dossier(dossier) do |d|
      SetAnnotationValue.set_piece_justificative(d, demarche.instructeur, champ, path)
    end
  end

  # Régression : set_annotation (templating) passe toujours des String ;
  # typed_query choisit la mutation GraphQL selon la classe Ruby de la valeur.
  # Une String sur une annotation IntegerNumber partait en mutation Text et le
  # serveur répondait « L'annotation ... n'existe pas ». set_value doit coercer
  # la String vers le type de l'annotation destination.
  context 'coercion des String vers le type de l’annotation' do
    let(:instructeur) { 'instructeur' }
    let(:dossier) { double('dossier', number: 653_455, id: 'RG9zc2llci02NTM0NTU=') }

    def annotation_double(typename, **readers)
      double('annotation', __typename: typename, id: 'Q2hhbXAtMTg3Njkx', label: 'annotation', **readers)
    end

    before { allow(SetAnnotationValue).to receive(:get_annotation).and_return(annotation) }

    context 'annotation IntegerNumber' do
      let(:annotation) { annotation_double('IntegerNumberChamp', int_value: nil) }

      it 'convertit la String en Integer avant la mutation' do
        expect(SetAnnotationValue).to receive(:raw_set_value)
          .with(dossier.id, instructeur, annotation.id, 1_000_000)
        expect(SetAnnotationValue.set_value(dossier, instructeur, 'annotation', '1000000')).to be true
      end

      context 'déjà à la même valeur' do
        let(:annotation) { annotation_double('IntegerNumberChamp', int_value: 1_000_000) }

        it 'ne réécrit pas (comparaison typée)' do
          expect(SetAnnotationValue).not_to receive(:raw_set_value)
          expect(SetAnnotationValue.set_value(dossier, instructeur, 'annotation', '1000000')).to be false
        end
      end
    end

    context 'annotation Checkbox' do
      let(:annotation) { annotation_double('CheckboxChamp', checked: false) }

      it "convertit 'Oui' en booléen avant la mutation" do
        expect(SetAnnotationValue).to receive(:raw_set_value)
          .with(dossier.id, instructeur, annotation.id, true)
        SetAnnotationValue.set_value(dossier, instructeur, 'annotation', 'Oui')
      end
    end

    context 'annotation Date' do
      let(:annotation) { annotation_double('DateChamp', date_value: nil) }

      it 'convertit une date au format français en Date avant la mutation' do
        expect(SetAnnotationValue).to receive(:raw_set_value)
          .with(dossier.id, instructeur, annotation.id, Date.new(2026, 7, 13))
        SetAnnotationValue.set_value(dossier, instructeur, 'annotation', '13/07/2026')
      end
    end

    context 'annotation Text' do
      let(:annotation) { annotation_double('TextChamp', value: nil) }

      it 'laisse la String telle quelle' do
        expect(SetAnnotationValue).to receive(:raw_set_value)
          .with(dossier.id, instructeur, annotation.id, 'libellé')
        SetAnnotationValue.set_value(dossier, instructeur, 'annotation', 'libellé')
      end
    end
  end

  context 'when parameters are good' do
    let(:dossier) { 308_727 }
    let(:demarche) { DemarcheActions.get_demarche(1488, 'test') }

    context 'champ texte', vcr: { cassette_name: 'set_annotation_text' } do
      let(:champ) { 'Champ texte' }
      it 'should set the value' do
        set(champ, 'v1')
        expect(get(champ).value).to eq('v1')
        set(champ, 'v2')
        expect(get(champ).value).to eq('v2')
      end
    end

    context 'champ entier', vcr: { cassette_name: 'set_annotation_int' } do
      let(:champ) { 'Champ entier' }
      it 'should set the value' do
        set(champ, 10)
        expect(get(champ).int_value).to eq('10')
        set(champ, 20)
        expect(get(champ).int_value).to eq('20')
      end
    end

    context 'champ date', vcr: { cassette_name: 'set_annotation_date' } do
      let(:champ) { 'Champ date' }
      it 'should set the value' do
        set(champ, Date.today)
        expect(Date.iso8601(get(champ).date_value)).to eq(Date.today)
        set(champ, 1.day.ago.to_date)
        expect(Date.iso8601(get(champ).date_value)).to eq(1.day.ago.to_date)
      end
    end

    context 'champ checkbox', vcr: { cassette_name: 'set_annotation_checkbox' } do
      let(:champ) { 'Champ checkbox' }
      it 'should set the value' do
        set(champ, true)
        expect(get(champ).checked).to eq(true)
        set(champ, false)
        expect(get(champ).checked).to eq(false)
      end
    end

    context 'champ piece justificative', vcr: { cassette_name: 'set_annotation_pj' } do
      let(:champ) { 'Champ pj' }
      it 'should set the value' do
        setpj(champ, 'spec/fixtures/models/publipostage.docx')
        file = get(champ).files.last
        expect(file.filename).to eq('publipostage.docx')
        expect(file.url).to be_truthy
        expect(file.checksum).to be_truthy
      end
    end
  end
end
