# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Calculs::ValueFlags do
  let(:controle) { FactoryBot.build :value_flags }
  let(:label) { 'Couverture maladie par l\'organisme d\'accueil' }
  let(:drapeaux) { %w[reponse_couverture_maladie_oui reponse_couverture_maladie_non reponse_couverture_maladie_incertaine] }

  def dossier_with(value)
    champ = double('DropDownListChamp', __typename: 'DropDownListChamp', label: label, value: value)
    double('Dossier', number: 42, champs: [champ], annotations: [])
  end

  subject do
    result = {}
    controle.dossier = dossier
    controle.process_row(dossier, result)
    result
  end

  context 'quand la réponse est « Oui »' do
    let(:dossier) { dossier_with('Oui') }

    it 'ne rend présent que le drapeau correspondant' do
      expect(subject['reponse_couverture_maladie_oui']).to eq 'Oui'
      expect(subject['reponse_couverture_maladie_non']).to eq ''
      expect(subject['reponse_couverture_maladie_incertaine']).to eq ''
    end
  end

  context 'quand la réponse est « Je ne sais pas »' do
    let(:dossier) { dossier_with('Je ne sais pas') }

    it 'rend présent le drapeau de la branche incertaine' do
      expect(subject['reponse_couverture_maladie_incertaine']).to eq 'Je ne sais pas'
      expect(subject['reponse_couverture_maladie_oui']).to eq ''
      expect(subject['reponse_couverture_maladie_non']).to eq ''
    end
  end

  context 'quand le champ est vide' do
    let(:dossier) { dossier_with('') }

    it 'pose tous les drapeaux, tous vides' do
      expect(subject.keys).to include(*drapeaux)
      expect(subject.values_at(*drapeaux)).to all(eq(''))
    end
  end

  context 'quand un champ usager et une annotation portent le même libellé' do
    let(:label) { 'Gratification' }
    let(:dossier) do
      champ = double('ChampUsager', __typename: 'DropDownListChamp', label: label, value: 'Prévue')
      annotation = double('Annotation', __typename: 'DropDownListChamp', label: label, value: 'Non prévue')
      double('Dossier', number: 42, champs: [champ], annotations: [annotation])
    end
    let(:controle) { Calculs::ValueFlags.new('champ' => label, 'source' => source, 'valeurs' => { 'Prévue' => 'gratification_du_stage' }) }

    context 'avec source: annotation' do
      let(:source) { 'annotation' }

      it 'lit la réponse de l\'agent' do
        expect(subject['gratification_du_stage']).to eq ''
      end
    end

    context 'avec source: champ' do
      let(:source) { 'champ' }

      it 'lit la réponse de l\'usager' do
        expect(subject['gratification_du_stage']).to eq 'Prévue'
      end
    end
  end

  context 'quand la réponse ne figure pas dans le mapping' do
    let(:dossier) { dossier_with('Peut-être') }

    it 'laisse tous les drapeaux vides' do
      expect(subject.values_at(*drapeaux)).to all(eq(''))
    end
  end
end
