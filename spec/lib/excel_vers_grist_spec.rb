# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExcelVersGrist do
  let(:params_valides) do
    {
      champ: 'Excel avec avis',
      etat_du_dossier: ['accepte'],
      grist: { 'doc_id' => 'doc', 'table_id' => 'Substances' }
    }
  end

  def fichier_double(filename: 'avis.xlsx', checksum: 'abc', url: 'https://example.test/a.xlsx')
    double('file', filename: filename, checksum: checksum, url: url)
  end

  def champ_double(label: 'Excel avec avis', typename: 'PieceJustificativeChamp', files: [])
    double('champ', label: label, __typename: typename, files: files)
  end

  def dossier_double(champs: [], annotations: [], state: 'accepte')
    double('dossier', number: 617_871, state: state, champs: champs, annotations: annotations)
  end

  describe 'validation de la configuration' do
    it 'accepte une configuration complète' do
      plugin = described_class.new(params_valides)
      expect(plugin.errors).to be_empty
      expect(plugin).to be_valid
    end

    it 'exige table_id' do
      plugin = described_class.new(params_valides.merge(grist: { 'doc_id' => 'doc' }))
      expect(plugin).not_to be_valid
      expect(plugin.errors.join).to match(/table_id/)
    end

    it 'exige doc_id' do
      plugin = described_class.new(params_valides.merge(grist: { 'table_id' => 'T' }))
      expect(plugin).not_to be_valid
      expect(plugin.errors.join).to match(/doc_id/)
    end

    it 'exige le champ source' do
      plugin = described_class.new(params_valides.except(:champ))
      expect(plugin).not_to be_valid
      expect(plugin.errors.join).to match(/champ/)
    end

    it 'accepte les options documentées' do
      plugin = described_class.new(params_valides.merge(
                                     feuille: 'Formulaire de saisie',
                                     ligne_entete: 17,
                                     colonnes: { 'A' => 'B' },
                                     options: { 'continuer_si_erreur' => true }
                                   ))
      expect(plugin.errors).to be_empty
    end

    it 'refuse une option inconnue' do
      plugin = described_class.new(params_valides.merge(fantaisie: 1))
      expect(plugin).not_to be_valid
      expect(plugin.errors.join).to match(/fantaisie/)
    end
  end

  describe 'sélection du fichier source' do
    subject(:plugin) { described_class.new(params_valides) }

    let(:demarche) { double('demarche', id: 1536) }

    it 'ne fait rien si le dossier n’est pas dans un état retenu' do
      expect(plugin).not_to receive(:traiter)
      plugin.process(demarche, dossier_double(state: 'en_construction'))
    end

    it 'ne fait rien si le champ est absent' do
      expect(plugin).not_to receive(:traiter)
      plugin.process(demarche, dossier_double(champs: [champ_double(label: 'Autre chose')]))
    end

    it 'ne fait rien si le champ n’est pas une pièce justificative' do
      expect(plugin).not_to receive(:traiter)
      plugin.process(demarche, dossier_double(champs: [champ_double(typename: 'TextChamp')]))
    end

    it 'ne fait rien si aucun fichier n’est un .xlsx' do
      champ = champ_double(files: [fichier_double(filename: 'avis.pdf')])
      expect(plugin).not_to receive(:traiter)
      plugin.process(demarche, dossier_double(champs: [champ]))
    end

    it 'retient les .xlsx quelle que soit la casse de l’extension' do
      champ = champ_double(files: [fichier_double(filename: 'AVIS.XLSX')])
      expect(plugin).to receive(:traiter)
      plugin.process(demarche, dossier_double(champs: [champ]))
    end

    # La donnée peut vivre côté usager (champ) ou côté agent (annotation
    # privée) : le plugin cherche dans les deux, sans présumer.
    it 'trouve le champ parmi les annotations privées' do
      champ = champ_double(files: [fichier_double])
      expect(plugin).to receive(:traiter)
      plugin.process(demarche, dossier_double(annotations: [champ]))
    end
  end

  describe 'gestion des erreurs' do
    let(:demarche) { double('demarche', id: 1536) }
    let(:dossier) { dossier_double(champs: [champ_double(files: [fichier_double])]) }

    it 'relève par défaut' do
      plugin = described_class.new(params_valides)
      allow(plugin).to receive(:traiter).and_raise(StandardError, 'boum')
      allow(Sentry).to receive(:capture_exception)

      expect { plugin.process(demarche, dossier) }.to raise_error(StandardError, 'boum')
      expect(Sentry).to have_received(:capture_exception)
    end

    it 'absorbe l’erreur quand continuer_si_erreur est vrai' do
      plugin = described_class.new(params_valides.merge(options: { 'continuer_si_erreur' => true }))
      allow(plugin).to receive(:traiter).and_raise(StandardError, 'boum')
      allow(Sentry).to receive(:capture_exception)

      expect { plugin.process(demarche, dossier) }.not_to raise_error
    end
  end
end
