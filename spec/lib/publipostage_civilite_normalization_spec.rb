# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe Publipostage, type: :model do
  describe '#normalize_civilites_in_data' do
    let(:publipostage) do
      described_class.new({
                            template: 'test.docx',
                            colonne: 'test'
                          })
    end

    context 'avec des civilités courtes' do
      it 'normalise M. en Monsieur' do
        data = { 'civilite' => 'M.' }
        result = publipostage.send(:normalize_civilites_in_data, data)
        expect(result['civilite']).to eq('Monsieur')
      end

      it 'normalise M en Monsieur' do
        data = { 'civilite' => 'M' }
        result = publipostage.send(:normalize_civilites_in_data, data)
        expect(result['civilite']).to eq('Monsieur')
      end

      it 'normalise Mme en Madame' do
        data = { 'civilite' => 'Mme' }
        result = publipostage.send(:normalize_civilites_in_data, data)
        expect(result['civilite']).to eq('Madame')
      end

      it 'normalise Mlle en Madame' do
        data = { 'civilite' => 'Mlle' }
        result = publipostage.send(:normalize_civilites_in_data, data)
        expect(result['civilite']).to eq('Madame')
      end
    end

    context 'avec des civilités longues déjà normalisées' do
      it 'garde Monsieur tel quel' do
        data = { 'civilite' => 'Monsieur' }
        result = publipostage.send(:normalize_civilites_in_data, data)
        expect(result['civilite']).to eq('Monsieur')
      end

      it 'garde Madame tel quel' do
        data = { 'civilite' => 'Madame' }
        result = publipostage.send(:normalize_civilites_in_data, data)
        expect(result['civilite']).to eq('Madame')
      end
    end

    context 'avec des structures imbriquées' do
      it 'normalise les civilités dans un hash imbriqué' do
        data = {
          'demandeur' => {
            'civilite' => 'M.',
            'nom' => 'Dupont',
            'prenom' => 'Jean'
          }
        }
        result = publipostage.send(:normalize_civilites_in_data, data)
        expect(result['demandeur']['civilite']).to eq('Monsieur')
        expect(result['demandeur']['nom']).to eq('Dupont')
      end

      it 'normalise les civilités dans un tableau' do
        data = {
          'personnes' => [
            { 'civilite' => 'M.', 'nom' => 'Dupont' },
            { 'civilite' => 'Mme', 'nom' => 'Martin' }
          ]
        }
        result = publipostage.send(:normalize_civilites_in_data, data)
        expect(result['personnes'][0]['civilite']).to eq('Monsieur')
        expect(result['personnes'][1]['civilite']).to eq('Madame')
      end

      it 'normalise les civilités dans une structure complexe' do
        data = {
          'bloc_repetable' => [
            {
              'investisseur' => {
                'civilite' => 'Mlle',
                'infos' => {
                  'adresse' => 'Test'
                }
              }
            }
          ]
        }
        result = publipostage.send(:normalize_civilites_in_data, data)
        expect(result['bloc_repetable'][0]['investisseur']['civilite']).to eq('Madame')
        expect(result['bloc_repetable'][0]['investisseur']['infos']['adresse']).to eq('Test')
      end
    end

    context 'avec des valeurs non-civilités' do
      it 'ne modifie pas les autres strings' do
        data = {
          'civilite' => 'M.',
          'nom' => 'Martin',
          'ville' => 'Papeete'
        }
        result = publipostage.send(:normalize_civilites_in_data, data)
        expect(result['civilite']).to eq('Monsieur')
        expect(result['nom']).to eq('Martin')
        expect(result['ville']).to eq('Papeete')
      end

      it 'préserve les types non-string' do
        data = {
          'civilite' => 'M.',
          'age' => 42,
          'actif' => true,
          'date' => Date.new(2024, 1, 1)
        }
        result = publipostage.send(:normalize_civilites_in_data, data)
        expect(result['civilite']).to eq('Monsieur')
        expect(result['age']).to eq(42)
        expect(result['actif']).to eq(true)
        expect(result['date']).to eq(Date.new(2024, 1, 1))
      end
    end
  end

  describe '#normalize_civilite_value' do
    let(:publipostage) do
      described_class.new({
                            template: 'test.docx',
                            colonne: 'test'
                          })
    end

    it 'normalise M. en Monsieur' do
      expect(publipostage.send(:normalize_civilite_value, 'M.')).to eq('Monsieur')
    end

    it 'normalise M en Monsieur' do
      expect(publipostage.send(:normalize_civilite_value, 'M')).to eq('Monsieur')
    end

    it 'normalise Mme en Madame' do
      expect(publipostage.send(:normalize_civilite_value, 'Mme')).to eq('Madame')
    end

    it 'normalise Mlle en Madame' do
      expect(publipostage.send(:normalize_civilite_value, 'Mlle')).to eq('Madame')
    end

    it 'retourne les autres valeurs inchangées' do
      expect(publipostage.send(:normalize_civilite_value, 'Dr')).to eq('Dr')
      expect(publipostage.send(:normalize_civilite_value, 'Pr')).to eq('Pr')
      expect(publipostage.send(:normalize_civilite_value, 'Dupont')).to eq('Dupont')
    end
  end

  describe 'skip régénération si seule civilité change', vcr: { cassette_name: 'publipostage_civilite_skip' } do
    # Ce test vérifie que si on a un ancien document avec "M." et qu'on reçoit
    # les mêmes données mais avec "Monsieur", on ne régénère PAS le document
    #
    # Note: Ce test nécessite un mock/stub plus complexe car il faut simuler
    # DossierData.find_by_folder_and_label avec des données existantes
    # Pour l'instant, nous testons uniquement les méthodes de normalisation
  end
end
# rubocop:enable Metrics/BlockLength
