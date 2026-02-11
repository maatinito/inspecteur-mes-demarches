# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe Publipostage, type: :model do
  describe '#normalize_for_comparison' do
    let(:publipostage) do
      described_class.new({
                            template: 'test.docx',
                            colonne: 'test'
                          })
    end

    context 'avec des civilités courtes' do
      it 'normalise M. en Monsieur' do
        data = { 'civilite' => 'M.' }
        result = publipostage.send(:normalize_for_comparison, data)
        expect(result['civilite']).to eq('Monsieur')
      end

      it 'normalise M en Monsieur' do
        data = { 'civilite' => 'M' }
        result = publipostage.send(:normalize_for_comparison, data)
        expect(result['civilite']).to eq('Monsieur')
      end

      it 'normalise Mme en Madame' do
        data = { 'civilite' => 'Mme' }
        result = publipostage.send(:normalize_for_comparison, data)
        expect(result['civilite']).to eq('Madame')
      end

      it 'normalise Mlle en Madame' do
        data = { 'civilite' => 'Mlle' }
        result = publipostage.send(:normalize_for_comparison, data)
        expect(result['civilite']).to eq('Madame')
      end
    end

    context 'avec des civilités longues déjà normalisées' do
      it 'garde Monsieur tel quel' do
        data = { 'civilite' => 'Monsieur' }
        result = publipostage.send(:normalize_for_comparison, data)
        expect(result['civilite']).to eq('Monsieur')
      end

      it 'garde Madame tel quel' do
        data = { 'civilite' => 'Madame' }
        result = publipostage.send(:normalize_for_comparison, data)
        expect(result['civilite']).to eq('Madame')
      end
    end

    context 'avec des dates contenant une heure' do
      it 'supprime la partie heure des dates' do
        data = { 'Date de dépôt' => ['09/02/2026 à 00h00'] }
        result = publipostage.send(:normalize_for_comparison, data)
        expect(result['Date de dépôt']).to eq(['09/02/2026'])
      end

      it 'supprime la partie heure avec une heure non nulle' do
        data = { 'Date de dépôt' => ['09/02/2026 à 14h30'] }
        result = publipostage.send(:normalize_for_comparison, data)
        expect(result['Date de dépôt']).to eq(['09/02/2026'])
      end

      it 'ne modifie pas les dates sans heure' do
        data = { 'Date de dépôt' => ['09/02/2026'] }
        result = publipostage.send(:normalize_for_comparison, data)
        expect(result['Date de dépôt']).to eq(['09/02/2026'])
      end
    end

    context 'avec des structures imbriquées' do
      it 'normalise civilités et dates dans un hash imbriqué' do
        data = {
          'demandeur' => {
            'civilite' => 'M.',
            'nom' => 'Dupont'
          },
          'Date de dépôt' => ['10/07/2023 à 09h55']
        }
        result = publipostage.send(:normalize_for_comparison, data)
        expect(result['demandeur']['civilite']).to eq('Monsieur')
        expect(result['demandeur']['nom']).to eq('Dupont')
        expect(result['Date de dépôt']).to eq(['10/07/2023'])
      end

      it 'normalise les civilités dans un tableau' do
        data = {
          'personnes' => [
            { 'civilite' => 'M.', 'nom' => 'Dupont' },
            { 'civilite' => 'Mme', 'nom' => 'Martin' }
          ]
        }
        result = publipostage.send(:normalize_for_comparison, data)
        expect(result['personnes'][0]['civilite']).to eq('Monsieur')
        expect(result['personnes'][1]['civilite']).to eq('Madame')
      end

      it 'normalise dans une structure complexe' do
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
        result = publipostage.send(:normalize_for_comparison, data)
        expect(result['bloc_repetable'][0]['investisseur']['civilite']).to eq('Madame')
        expect(result['bloc_repetable'][0]['investisseur']['infos']['adresse']).to eq('Test')
      end
    end

    context 'avec des valeurs non-civilités et non-dates' do
      it 'ne modifie pas les autres strings' do
        data = {
          'nom' => 'Martin',
          'ville' => 'Papeete'
        }
        result = publipostage.send(:normalize_for_comparison, data)
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
        result = publipostage.send(:normalize_for_comparison, data)
        expect(result['civilite']).to eq('Monsieur')
        expect(result['age']).to eq(42)
        expect(result['actif']).to eq(true)
        expect(result['date']).to eq(Date.new(2024, 1, 1))
      end
    end

    context 'comparaison ancien/nouveau format' do
      it 'considère identiques les données avec civilité M vs Monsieur' do
        old_data = { 'Civilité' => ['M'], 'Nom' => ['Dupont'] }
        new_data = { 'Civilité' => ['Monsieur'], 'Nom' => ['Dupont'] }
        normalized_old = publipostage.send(:normalize_for_comparison, old_data)
        normalized_new = publipostage.send(:normalize_for_comparison, new_data)
        expect(normalized_old).to eq(normalized_new)
      end

      it 'considère identiques les données avec date sans/avec heure' do
        old_data = { 'Date de dépôt' => ['09/02/2026'], 'Nom' => ['Dupont'] }
        new_data = { 'Date de dépôt' => ['09/02/2026 à 00h00'], 'Nom' => ['Dupont'] }
        normalized_old = publipostage.send(:normalize_for_comparison, old_data)
        normalized_new = publipostage.send(:normalize_for_comparison, new_data)
        expect(normalized_old).to eq(normalized_new)
      end

      it 'considère identiques les données avec les deux changements combinés' do
        old_data = {
          'Civilité' => ['M'],
          'Nom' => ['MAO'],
          'Date de dépôt' => ['09/02/2026'],
          'Dossier' => 609_386
        }
        new_data = {
          'Civilité' => ['Monsieur'],
          'Nom' => ['MAO'],
          'Date de dépôt' => ['09/02/2026 à 09h55'],
          'Dossier' => 609_386
        }
        normalized_old = publipostage.send(:normalize_for_comparison, old_data)
        normalized_new = publipostage.send(:normalize_for_comparison, new_data)
        expect(normalized_old).to eq(normalized_new)
      end

      it 'détecte les vrais changements de données' do
        old_data = { 'Nom' => ['MAO'], 'Date de dépôt' => ['09/02/2026'] }
        new_data = { 'Nom' => ['DUPONT'], 'Date de dépôt' => ['09/02/2026'] }
        normalized_old = publipostage.send(:normalize_for_comparison, old_data)
        normalized_new = publipostage.send(:normalize_for_comparison, new_data)
        expect(normalized_old).not_to eq(normalized_new)
      end
    end
  end

  describe '#normalize_string_value' do
    let(:publipostage) do
      described_class.new({
                            template: 'test.docx',
                            colonne: 'test'
                          })
    end

    it 'normalise M. en Monsieur' do
      expect(publipostage.send(:normalize_string_value, 'M.')).to eq('Monsieur')
    end

    it 'normalise M en Monsieur' do
      expect(publipostage.send(:normalize_string_value, 'M')).to eq('Monsieur')
    end

    it 'normalise Mme en Madame' do
      expect(publipostage.send(:normalize_string_value, 'Mme')).to eq('Madame')
    end

    it 'normalise Mlle en Madame' do
      expect(publipostage.send(:normalize_string_value, 'Mlle')).to eq('Madame')
    end

    it 'supprime la partie heure des dates' do
      expect(publipostage.send(:normalize_string_value, '09/02/2026 à 14h30')).to eq('09/02/2026')
    end

    it 'ne modifie pas les dates sans heure' do
      expect(publipostage.send(:normalize_string_value, '09/02/2026')).to eq('09/02/2026')
    end

    it 'retourne les autres valeurs inchangées' do
      expect(publipostage.send(:normalize_string_value, 'Dupont')).to eq('Dupont')
      expect(publipostage.send(:normalize_string_value, 'Papeete')).to eq('Papeete')
    end
  end
end
# rubocop:enable Metrics/BlockLength
