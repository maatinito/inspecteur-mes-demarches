# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SetAnnotationValue do
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

  context 'when parameters are good' do
    let(:dossier) { 286690 }
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
        expect(get(champ).value).to eq('10')
        set(champ, 20)
        expect(get(champ).value).to eq('20')
      end
    end

    context 'champ date', vcr: { cassette_name: 'set_annotation_date' } do
      let(:champ) { 'Champ date' }
      it 'should set the value' do
        set(champ, Date.today)
        expect(Date.iso8601(get(champ).value)).to eq(Date.today)
        set(champ, 1.day.ago.to_date)
        expect(Date.iso8601(get(champ).value)).to eq(1.day.ago.to_date)
      end
    end

    context 'champ checkbox', vcr: { cassette_name: 'set_annotation_checkbox' } do
      let(:champ) { 'Champ checkbox' }
      it 'should set the value' do
        set(champ, true)
        expect(get(champ).value).to eq(true)
        set(champ, false)
        expect(get(champ).value).to eq(false)
      end
    end

    context 'champ piece justificative', vcr: { cassette_name: 'set_annotation_pj' } do
      let(:champ) { 'Champ pj' }
      it 'should set the value' do
        setpj(champ, '.rspec')
        file = get(champ).file
        expect(file.filename).to eq('.rspec')
        expect(file.url).to be_truthy
        expect(file.checksum).to be_truthy
      end
    end
  end
end
