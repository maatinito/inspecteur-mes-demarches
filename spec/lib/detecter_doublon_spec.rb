# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DetecterDoublon do
  let(:instructeur_id) { 'instructeur-1' }
  let(:demarche) { instance_double(Demarche, id: 3288, instructeur: instructeur_id) }

  let(:champ_immat) do
    double('champ', id: 'c1', label: 'Immatriculation du navire (PY)',
                    __typename: 'TextChamp', value: 'PY-12345')
  end

  let(:dossier_number) { 100 }
  let(:state) { 'en_construction' }
  let(:dossier_labels) { [] }
  let(:dossier_depose_at) { 2.days.ago }
  let(:dossier) do
    double('dossier',
           id: "gid://Dossier/#{dossier_number}",
           number: dossier_number,
           state:,
           date_depot: dossier_depose_at,
           champs: [champ_immat],
           annotations: [],
           labels: dossier_labels)
  end

  let(:base_params) do
    { cle: '{Immatriculation du navire (PY)}' }
  end

  describe 'paramétrage' do
    it 'requiert cle' do
      expect(described_class.new({}).valid?).to be false
    end

    it 'accepte etats_doublons, purge_after_months, quand_*, etat_du_dossier' do
      checker = described_class.new(base_params.merge(
                                      etats_doublons: %w[en_instruction],
                                      purge_after_months: 8,
                                      etat_du_dossier: %w[en_construction],
                                      quand_doublon: [],
                                      quand_unique: []
                                    ))
      expect(checker.valid?).to be true
    end
  end

  describe '#check — registre' do
    let(:checker) { described_class.new(base_params) }

    it 'insère une entrée pour un dossier en construction' do
      checker.demarche = demarche
      checker.check(dossier)
      entry = DossierDoublon.find_by(dossier_number:)
      expect(entry).to have_attributes(
        demarche_id: demarche.id,
        cle: 'PY-12345',
        state: 'en_construction'
      )
    end

    it 'normalise la clé (majuscules + suppression espaces)' do
      allow(champ_immat).to receive(:value).and_return('  py 1234 pl  ')
      checker.demarche = demarche
      checker.check(dossier)
      expect(DossierDoublon.find_by(dossier_number:).cle).to eq 'PY1234PL'
    end

    it 'supprime du registre quand le dossier passe à refuse' do
      DossierDoublon.create!(demarche_id: demarche.id, dossier_number:, cle: 'PY-12345',
                             state: 'en_instruction', depose_at: 2.days.ago)
      allow(dossier).to receive(:state).and_return('refuse')
      checker.demarche = demarche
      checker.check(dossier)
      expect(DossierDoublon.find_by(dossier_number:)).to be_nil
    end

    it 'supprime du registre quand la clé est vidée' do
      DossierDoublon.create!(demarche_id: demarche.id, dossier_number:, cle: 'PY-12345',
                             state: 'en_construction', depose_at: 2.days.ago)
      allow(champ_immat).to receive(:value).and_return('')
      checker.demarche = demarche
      checker.check(dossier)
      expect(DossierDoublon.find_by(dossier_number:)).to be_nil
    end
  end

  describe '#check — clé composite' do
    let(:champ_nom) { double('nom', label: 'Nom', __typename: 'TextChamp', value: 'Cousteau') }
    let(:champ_prenom) { double('prenom', label: 'Prenom', __typename: 'TextChamp', value: 'Jacques') }
    let(:dossier_compose) do
      double('dossier_compose', id: 'd2', number: 200, state: 'en_construction',
                                date_depot: 2.days.ago,
                                champs: [champ_nom, champ_prenom], annotations: [], labels: [])
    end
    let(:checker) { described_class.new(cle: '{Nom}-{Prenom}') }

    it 'compose la clé à partir de plusieurs champs' do
      checker.demarche = demarche
      checker.check(dossier_compose)
      expect(DossierDoublon.find_by(dossier_number: 200).cle).to eq 'COUSTEAU-JACQUES'
    end
  end

  describe '#check — séparation etats_doublons / etat_du_dossier' do
    let(:checker) do
      described_class.new(base_params.merge(
                            etat_du_dossier: %w[en_construction en_instruction],
                            etats_doublons: %w[en_construction en_instruction accepte]
                          ))
    end

    it 'ne fire pas les actions sur un accepté mais le maintient dans le registre' do
      allow(dossier).to receive(:state).and_return('accepte')
      task = double('task', name: 'fake', valid?: true, updated_dossiers: Set.new, dossiers_to_recheck: Set.new)
      allow(task).to receive(:demarche=)
      allow(task).to receive(:process)
      allow(InspectorTask).to receive(:create_tasks).and_return([task])
      DossierDoublon.create!(demarche_id: demarche.id, dossier_number: 99, cle: 'PY-12345',
                             state: 'en_instruction', depose_at: 3.days.ago)
      checker_q = described_class.new(base_params.merge(quand_doublon: [{ 'fake' => {} }]))
      checker_q.demarche = demarche
      checker_q.check(dossier)
      expect(task).not_to have_received(:process)
      expect(DossierDoublon.find_by(dossier_number:).state).to eq 'accepte'
    end

    it 'détecte un accepté comme doublon pour un dossier en construction' do
      DossierDoublon.create!(demarche_id: demarche.id, dossier_number: 99, cle: 'PY-12345',
                             state: 'accepte', depose_at: 3.days.ago)
      task = double('task', name: 'fake', valid?: true, updated_dossiers: Set.new, dossiers_to_recheck: Set.new)
      allow(task).to receive(:demarche=)
      allow(task).to receive(:process)
      allow(InspectorTask).to receive(:create_tasks).and_return([task])
      checker_q = described_class.new(base_params.merge(quand_doublon: [{ 'fake' => {} }]))
      checker_q.demarche = demarche
      checker_q.check(dossier)
      expect(task).to have_received(:process)
    end

    it 'ignore un dossier refusé comme doublon' do
      DossierDoublon.create!(demarche_id: demarche.id, dossier_number: 99, cle: 'PY-12345',
                             state: 'refuse', depose_at: 3.days.ago)
      task = double('task', name: 'fake', valid?: true, updated_dossiers: Set.new, dossiers_to_recheck: Set.new)
      allow(task).to receive(:demarche=)
      allow(task).to receive(:process)
      allow(InspectorTask).to receive(:create_tasks).and_return([task])
      checker_q = described_class.new(base_params.merge(quand_doublon: [{ 'fake' => {} }]))
      checker_q.demarche = demarche
      checker_q.check(dossier)
      expect(task).not_to have_received(:process)
    end
  end

  describe '#check — fire des actions' do
    let(:fake_task) do
      double('task', name: 'fake_task', valid?: true,
                     updated_dossiers: Set.new, dossiers_to_recheck: Set.new)
    end

    before do
      allow(fake_task).to receive(:demarche=)
      allow(fake_task).to receive(:process)
      allow(InspectorTask).to receive(:create_tasks).and_return([fake_task])
    end

    it 'fire quand_doublon en présence de doublons' do
      DossierDoublon.create!(demarche_id: demarche.id, dossier_number: 99, cle: 'PY-12345',
                             state: 'en_instruction', depose_at: 3.days.ago)
      checker = described_class.new(base_params.merge(quand_doublon: [{ 'fake_task' => {} }]))
      checker.demarche = demarche
      checker.check(dossier)
      expect(fake_task).to have_received(:process).with(demarche, dossier)
    end

    it 'fire quand_unique en absence de doublons' do
      checker = described_class.new(base_params.merge(quand_unique: [{ 'fake_task' => {} }]))
      checker.demarche = demarche
      checker.check(dossier)
      expect(fake_task).to have_received(:process).with(demarche, dossier)
    end

    it 'ignore une liste vide' do
      checker = described_class.new(base_params)
      checker.demarche = demarche
      checker.check(dossier)
      expect(InspectorTask).not_to have_received(:create_tasks)
    end
  end

  describe '#check — substitution des variables' do
    it 'remplace doublons_refs, doublons_count, cle dans les params des sous-tâches' do
      DossierDoublon.create!(demarche_id: demarche.id, dossier_number: 50, cle: 'PY-12345',
                             state: 'en_instruction', depose_at: 4.days.ago)
      DossierDoublon.create!(demarche_id: demarche.id, dossier_number: 99, cle: 'PY-12345',
                             state: 'accepte', depose_at: 3.days.ago)

      captured = nil
      allow(InspectorTask).to receive(:create_tasks) do |defs|
        captured = defs
        []
      end

      checker = described_class.new(base_params.merge(
                                      quand_doublon: [{
                                        'set_annotation' => {
                                          'annotation' => 'Doublon',
                                          'valeur' => 'cle={cle} count={doublons_count} refs={doublons_refs}'
                                        }
                                      }]
                                    ))
      checker.demarche = demarche
      checker.check(dossier)

      params = captured.first['set_annotation']
      expect(params['valeur']).to eq 'cle=PY-12345 count=2 refs=#50, #99'
    end

    it 'résout aussi les champs/attributs du dossier via instanciate (number, ternaire, prefix/postfix)' do
      DossierDoublon.create!(demarche_id: demarche.id, dossier_number: 99, cle: 'PY-12345',
                             state: 'en_instruction', depose_at: 3.days.ago)
      captured = nil
      allow(InspectorTask).to receive(:create_tasks) do |defs|
        captured = defs
        []
      end

      checker = described_class.new(base_params.merge(
                                      quand_doublon: [{
                                        'set_annotation' => {
                                          'numero' => 'PC {number}',
                                          'phrase' => '{doublons trouvés: ;doublons_count;}',
                                          'verdict' => '{doublons_count ? "doublon" : "ok"}'
                                        }
                                      }]
                                    ))
      checker.demarche = demarche
      checker.check(dossier)

      params = captured.first['set_annotation']
      expect(params['numero']).to eq 'PC 100'
      expect(params['phrase']).to eq 'doublons trouvés: 1'
      expect(params['verdict']).to eq 'doublon'
    end
  end

  describe '#check — recheck des frères' do
    # Asymétrie : seuls les dossiers déposés APRÈS le courant sont réveillés.
    # Le légitime (le plus ancien) ne se remet jamais en cause à cause d'un postérieur.
    it 'réveille les frères postérieurs (depose_at > self.depose_at) sur la même clé' do
      DossierDoublon.create!(demarche_id: demarche.id, dossier_number: 200, cle: 'PY-12345',
                             state: 'en_instruction', depose_at: 1.day.ago)
      checker = described_class.new(base_params)
      checker.demarche = demarche
      checker.check(dossier)
      expect(checker.dossiers_to_recheck).to include(200)
    end

    it 'ne réveille pas les frères antérieurs' do
      DossierDoublon.create!(demarche_id: demarche.id, dossier_number: 50, cle: 'PY-12345',
                             state: 'en_instruction', depose_at: 4.days.ago)
      checker = described_class.new(base_params)
      checker.demarche = demarche
      checker.check(dossier)
      expect(checker.dossiers_to_recheck).not_to include(50)
    end

    it 'le plus ancien reste légitime (unique) même avec un frère postérieur' do
      DossierDoublon.create!(demarche_id: demarche.id, dossier_number: 200, cle: 'PY-12345',
                             state: 'en_instruction', depose_at: 1.day.ago)
      task = double('task', name: 'fake', valid?: true, updated_dossiers: Set.new, dossiers_to_recheck: Set.new)
      allow(task).to receive(:demarche=)
      allow(task).to receive(:process)
      allow(InspectorTask).to receive(:create_tasks).and_return([task])
      checker = described_class.new(base_params.merge(quand_doublon: [{ 'fake' => {} }]))
      checker.demarche = demarche
      checker.check(dossier)
      expect(task).not_to have_received(:process)
    end
  end

  describe "#check — message à l'usager" do
    it 'ajoute un message si paramètre `message` et doublon détecté (instanciation OK)' do
      DossierDoublon.create!(demarche_id: demarche.id, dossier_number: 99, cle: 'PY-12345',
                             state: 'en_instruction', depose_at: 3.days.ago)
      checker = described_class.new(base_params.merge(
                                      message: 'Une demande pour le navire {cle} existe déjà ({doublons_refs}).'
                                    ))
      checker.demarche = demarche
      checker.check(dossier)
      expect(checker.messages.size).to eq 1
      expect(checker.messages.first.message).to eq 'Une demande pour le navire PY-12345 existe déjà (#99).'
    end

    it "n'ajoute pas de message si aucun doublon" do
      checker = described_class.new(base_params.merge(message: 'Doublon : {doublons_refs}'))
      checker.demarche = demarche
      checker.check(dossier)
      expect(checker.messages).to be_empty
    end

    it "n'ajoute pas de message si paramètre `message` absent (même avec doublon)" do
      DossierDoublon.create!(demarche_id: demarche.id, dossier_number: 99, cle: 'PY-12345',
                             state: 'en_instruction', depose_at: 3.days.ago)
      checker = described_class.new(base_params)
      checker.demarche = demarche
      checker.check(dossier)
      expect(checker.messages).to be_empty
    end
  end

  describe '#process — interdit' do
    it "raise pour empêcher l'usage dans when_ok: (recheck non propagé)" do
      checker = described_class.new(base_params)
      expect { checker.process(demarche, dossier) }
        .to raise_error(NotImplementedError, /controles:/)
    end
  end
end
