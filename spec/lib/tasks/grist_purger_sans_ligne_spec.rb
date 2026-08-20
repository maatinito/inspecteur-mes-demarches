# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'grist:purger_sans_ligne', type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('grist:purger_sans_ligne')
  end

  let(:task) { Rake::Task['grist:purger_sans_ligne'] }
  let(:table) { instance_double(Grist::Table) }
  let(:records) { [] }

  before do
    allow(Grist::Config).to receive(:table).and_return(table)
    allow(table).to receive(:columns).and_return({ 'Ligne' => {}, 'Dossier' => {} })
    allow(table).to receive(:list_records).and_return({ 'records' => records })
    allow(table).to receive(:delete_records)
  end

  after { task.reenable }

  def purger(pour_de_vrai = 'oui')
    task.invoke('doc1', 'Substances', 'Ligne', pour_de_vrai, 'Dossier')
  end

  def ligne(row_id, dossier, numero = nil)
    { 'id' => row_id, 'fields' => { 'Dossier' => dossier, 'Ligne' => numero } }
  end

  context "quand le dossier n'a pas encore été repris par le robot" do
    # Ses lignes héritées sont la seule copie existante : les supprimer serait
    # une perte sèche, pas une libération.
    let(:records) { [ligne(1, 5), ligne(2, 5)] }

    it 'conserve toutes ses lignes héritées' do
      purger

      expect(table).not_to have_received(:delete_records)
    end
  end

  context 'quand le dossier porte déjà des lignes recopiées par le robot' do
    let(:records) { [ligne(1, 5, 1), ligne(2, 5, 2), ligne(3, 5)] }

    it 'supprime les seules lignes héritées, devenues des doublons' do
      purger

      expect(table).to have_received(:delete_records).with([3])
    end
  end

  context 'quand une ligne héritée est rattachée à un dossier vide' do
    # Sans rattachement, aucune preuve de reprise n'est possible : on garde.
    let(:records) { [ligne(1, nil), ligne(2, 0), ligne(3, 7, 1), ligne(4, 7)] }

    it 'ne purge que la ligne dont le dossier est identifié et repris' do
      purger

      expect(table).to have_received(:delete_records).with([4])
    end
  end

  context 'en simulation (quatrième argument absent)' do
    let(:records) { [ligne(1, 5, 1), ligne(2, 5)] }

    it "n'émet aucune suppression" do
      purger('non')

      expect(table).not_to have_received(:delete_records)
    end
  end

  context "quand la colonne de rattachement n'existe pas dans la table" do
    let(:records) { [ligne(1, 5, 1), ligne(2, 5)] }

    before { allow(table).to receive(:columns).and_return({ 'Ligne' => {} }) }

    it 'interrompt la tâche plutôt que de purger sans garde-fou' do
      expect { purger }.to raise_error(SystemExit)
      expect(table).not_to have_received(:delete_records)
    end
  end

  context 'quand plusieurs dossiers sont mêlés' do
    let(:records) do
      [
        ligne(1, 5, 1), ligne(2, 5),          # 5 : repris  -> la 2 est purgeable
        ligne(3, 6), ligne(4, 6),             # 6 : pas repris -> on garde
        ligne(5, 7, 1), ligne(6, 7), ligne(7, 7) # 7 : repris -> 6 et 7 purgeables
      ]
    end

    it 'ne purge que les lignes des dossiers repris' do
      purger

      expect(table).to have_received(:delete_records).with([2, 6, 7])
    end
  end
end
