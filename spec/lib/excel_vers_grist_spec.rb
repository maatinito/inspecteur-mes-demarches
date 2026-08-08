# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
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

  describe 'garde par empreinte' do
    subject(:plugin) { described_class.new(params_valides) }

    it 'concatène les empreintes triées, pour être insensible à l’ordre des fichiers' do
      a = fichier_double(filename: 'a.xlsx', checksum: 'zzz')
      b = fichier_double(filename: 'b.xlsx', checksum: 'aaa')

      expect(plugin.send(:empreinte_source, [a, b])).to eq('aaa,zzz')
      expect(plugin.send(:empreinte_source, [b, a])).to eq('aaa,zzz')
    end

    it 'considère le dossier à jour quand l’empreinte stockée est identique' do
      ligne = { 'fields' => { 'excel_checksum' => 'aaa,zzz' } }
      expect(plugin.send(:a_jour?, 'aaa,zzz', ligne)).to be true
    end

    it 'retraite quand l’empreinte diffère' do
      ligne = { 'fields' => { 'excel_checksum' => 'ancienne' } }
      expect(plugin.send(:a_jour?, 'aaa', ligne)).to be false
    end

    it 'retraite quand la colonne porte la sentinelle' do
      ligne = { 'fields' => { 'excel_checksum' => '-' } }
      expect(plugin.send(:a_jour?, 'aaa', ligne)).to be false
    end

    it 'retraite quand la ligne principale n’existe pas encore' do
      expect(plugin.send(:a_jour?, 'aaa', nil)).to be false
    end

    it 'retraite quand la colonne est vide' do
      expect(plugin.send(:a_jour?, 'aaa', { 'fields' => { 'excel_checksum' => '' } })).to be false
    end

    it 'permet de renommer la colonne d’empreinte' do
      autre = described_class.new(params_valides.merge(options: { 'colonne_empreinte' => 'Empreinte' }))
      expect(autre.send(:colonne_empreinte)).to eq('Empreinte')
      expect(autre.send(:a_jour?, 'aaa', { 'fields' => { 'Empreinte' => 'aaa' } })).to be true
    end
  end

  describe 'création de la colonne d’empreinte' do
    subject(:plugin) { described_class.new(params_valides) }

    let(:table) { instance_double(Grist::Table) }

    it 'crée la colonne avec la sentinelle comme valeur par défaut' do
      allow(table).to receive(:columns).and_return({})
      allow(table).to receive(:create_columns)

      plugin.send(:ensure_colonne_empreinte, table)

      expect(table).to have_received(:create_columns) do |data|
        champ = data.first
        expect(champ[:id]).to eq('excel_checksum')
        # isFormula: false + formula non vide = valeur par défaut Grist. Toute
        # ligne créée ensuite entre d'office dans l'état « à traiter ».
        expect(champ[:fields][:isFormula]).to be false
        expect(champ[:fields][:formula]).to eq('"-"')
      end
    end

    it 'ne recrée pas une colonne existante' do
      allow(table).to receive(:columns).and_return('excel_checksum' => { type: 'Text' })
      expect(table).not_to receive(:create_columns)

      plugin.send(:ensure_colonne_empreinte, table)
    end
  end

  describe 'mapping des colonnes' do
    def colonne(nom, type: 'Text', index: 0)
      Excel::ColumnDescriptor.new(nom: nom, en_tete_brut: nom, index: index, type_infere: type)
    end

    it 'sans configuration : la cible est la source, le type est celui inféré' do
      plugin = described_class.new(params_valides)
      cols = [colonne('Nom'), colonne('Montant', type: 'Numeric', index: 1)]

      expect(plugin.send(:mapping, cols)).to eq(
        'Nom' => { cible: 'Nom', type: 'Text' },
        'Montant' => { cible: 'Montant', type: 'Numeric' }
      )
    end

    it 'accepte la forme courte source: cible' do
      plugin = described_class.new(params_valides.merge(colonnes: { 'Substances actives' => 'Nom' }))

      expect(plugin.send(:mapping, [colonne('Substances actives')]))
        .to eq('Substances actives' => { cible: 'Nom', type: 'Text' })
    end

    it 'accepte la forme longue avec type forcé' do
      plugin = described_class.new(params_valides.merge(
                                     colonnes: { 'Poids/Volume total' => { 'cible' => 'Poids_volume_total', 'type' => 'numeric' } }
                                   ))

      expect(plugin.send(:mapping, [colonne('Poids/Volume total')]))
        .to eq('Poids/Volume total' => { cible: 'Poids_volume_total', type: 'Numeric' })
    end

    it 'garde le type inféré si le type déclaré est inconnu' do
      plugin = described_class.new(params_valides.merge(
                                     colonnes: { 'Montant' => { 'cible' => 'M', 'type' => 'fantaisie' } }
                                   ))

      expect(plugin.send(:mapping, [colonne('Montant', type: 'Numeric')]))
        .to eq('Montant' => { cible: 'M', type: 'Numeric' })
    end

    it 'ignore une colonne source absente du fichier et le rapporte' do
      plugin = described_class.new(params_valides.merge(colonnes: { 'Absente' => 'X' }))

      expect(plugin.send(:mapping, [])).to eq({})
      expect(plugin.erreurs_metier.join).to match(/Absente/)
    end

    it 'ne retient que les colonnes déclarées quand un mapping est fourni' do
      plugin = described_class.new(params_valides.merge(colonnes: { 'Nom' => 'Nom' }))

      expect(plugin.send(:mapping, [colonne('Nom'), colonne('Ignoree', index: 1)]).keys).to eq(['Nom'])
    end
  end

  describe 'création des colonnes manquantes' do
    let(:table) { instance_double(Grist::Table) }
    let(:correspondance) { { 'Nom' => { cible: 'Nom', type: 'Text' } } }

    it 'crée les colonnes cibles absentes' do
      allow(table).to receive(:columns).and_return('Ligne' => { type: 'Int' })
      allow(table).to receive(:create_columns)
      plugin = described_class.new(params_valides)

      expect(plugin.send(:ensure_colonnes, table, correspondance)).to eq(['Nom'])
      expect(table).to have_received(:create_columns) do |data|
        expect(data.first[:id]).to eq('Nom')
        expect(data.first[:fields][:type]).to eq('Text')
      end
    end

    it 'ne crée rien quand creer_colonnes_manquantes est faux' do
      allow(table).to receive(:columns).and_return({})
      plugin = described_class.new(params_valides.merge(options: { 'creer_colonnes_manquantes' => false }))

      expect(table).not_to receive(:create_columns)
      expect(plugin.send(:ensure_colonnes, table, correspondance)).to eq([])
    end

    it 'ne crée rien quand toutes les colonnes existent' do
      allow(table).to receive(:columns).and_return('Nom' => { type: 'Text' })
      plugin = described_class.new(params_valides)

      expect(table).not_to receive(:create_columns)
      expect(plugin.send(:ensure_colonnes, table, correspondance)).to eq([])
    end

    # Le type d'une colonne existante n'est jamais modifié : le parcours assumé
    # est de traiter un premier fichier, ajuster les types à la main dans Grist,
    # puis retraiter.
    it 'ne modifie jamais le type d’une colonne existante et rapporte le conflit' do
      allow(table).to receive(:columns).and_return('Montant' => { id: 'Montant', type: 'Text' })
      plugin = described_class.new(params_valides)

      expect(table).not_to receive(:update_column)
      plugin.send(:ensure_colonnes, table, 'Montant' => { cible: 'Montant', type: 'Numeric' })

      expect(plugin.erreurs_metier.join).to match(/Montant.*Text.*Numeric/)
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
# rubocop:enable Metrics/BlockLength
