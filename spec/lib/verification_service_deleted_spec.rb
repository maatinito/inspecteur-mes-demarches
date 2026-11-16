# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe VerificationService do
  let(:service) { VerificationService.new }

  describe '#check_demarche (hook deleted)' do
    let(:ancien_curseur) { Time.zone.parse('2026-11-01 08:00') }
    let(:demarche) { create(:demarche, id: 3604, checked_at: ancien_curseur) }
    let(:ecouteuse) do
      Class.new(InspectorTask) do
        attr_reader :appels
        attr_accessor :echecs

        def deleted(demarche, number)
          (@appels ||= []) << [demarche, number]
          erreur = (@echecs || {})[number]
          raise erreur if erreur

          nil
        end

        def numeros
          (@appels || []).map(&:last)
        end
      end
    end
    let(:flux) { [1, 2] }

    def tache(echecs = {})
      ecouteuse.new({}).tap { |t| t.echecs = echecs }
    end

    def passer(controls)
      service.send(:check_demarche, controls, 3604, false, 'conf')
    end

    def en_attente
      SuppressionEnAttente.where(demarche_id: 3604).order(:dossier).pluck(:dossier)
    end

    before do
      allow(DemarcheActions).to receive(:get_demarche).and_return(demarche)
      allow(DossierActions).to receive(:on_dossiers)
      allow(DossierActions).to receive(:on_deleted_dossiers) { |*, &bloc| flux.each(&bloc) }
      allow(DossierActions).to receive(:on_dossier).and_return(nil)
      allow(service).to receive(:current_user_has_access_to?).and_return(true)
      allow(service).to receive(:report_error)
      allow(Referentiel::Alerte).to receive(:signaler)
      service.instance_variable_set(:@ok_tasks, [])
    end

    it "n'interroge pas les suppressions quand aucune tâche ne les écoute, et laisse la file intacte" do
      SuppressionEnAttente.create!(demarche_id: 3604, dossier: 9)

      passer([InspectorTask.new({})])

      expect(DossierActions).not_to have_received(:on_deleted_dossiers)
      expect(en_attente).to eq([9])
      expect(demarche.reload.checked_at).to be > ancien_curseur
    end

    it 'avance le curseur à l\'heure de début quand personne ne l\'a touché pendant le passage' do
      passer([InspectorTask.new({})])

      expect(demarche.reload.checked_at).to be > ancien_curseur
      expect(demarche.checked_at).to be_within(1.minute).of(Time.zone.now)
    end

    it 'ne rattrape pas un curseur remis au début pendant le passage' do
      allow(DossierActions).to receive(:on_dossiers) do
        Demarche.where(id: 3604).update_all(checked_at: DossierActions::EPOCH)
      end

      passer([InspectorTask.new({})])

      expect(Demarche.find(3604).checked_at).to eq(DossierActions::EPOCH)
    end

    it 'appelle deleted sur chaque tâche qui le surcharge, avec le curseur de la démarche' do
      controle = tache
      ok = tache
      service.instance_variable_set(:@ok_tasks, [ok])

      passer([controle, InspectorTask.new({})])

      expect(DossierActions).to have_received(:on_deleted_dossiers).once.with(3604, ancien_curseur)
      expect(controle.appels).to eq([[demarche, 1], [demarche, 2]])
      expect(ok.appels).to eq([[demarche, 1], [demarche, 2]])
      expect(en_attente).to be_empty
    end

    it 'continue après une tâche en erreur, met le numéro en attente et avance le curseur' do
      en_erreur = tache(1 => StandardError.new('boum'))
      suivante = tache
      allow(Rails.env).to receive(:production?).and_return(true)

      expect { passer([en_erreur, suivante]) }.not_to raise_error

      expect(service).to have_received(:report_error).with('Error applying deleted', kind_of(StandardError)).once
      expect(suivante.numeros).to eq([1, 2])
      expect(en_attente).to eq([1])
      expect(demarche.reload.checked_at).to be > ancien_curseur
    end

    it 'un refus enregistre le numéro en attente, alerte sans lever, et le curseur avance' do
      refus = Referentiel::Verrou::Refus.new('Référentiel refusé', nil)
      flux.replace([12])
      tache = tache(12 => refus)

      expect { passer([tache]) }.not_to raise_error

      expect(Referentiel::Alerte).to have_received(:signaler).with(refus)
      expect(service).not_to have_received(:report_error)
      expect(en_attente).to eq([12])
      expect(demarche.reload.checked_at).to be > ancien_curseur
    end

    it 'rejoue au passage suivant un numéro en attente, flux vide, et retire la ligne après succès' do
      refus = Referentiel::Verrou::Refus.new('Référentiel refusé', nil)
      flux.replace([12])
      tache = tache(12 => refus)
      passer([tache])
      expect(en_attente).to eq([12])

      flux.clear
      tache.echecs = {}
      passer([tache])

      expect(tache.numeros).to eq([12, 12])
      expect(en_attente).to be_empty
    end

    it 'un numéro en échec pour une tâche sur deux reste en attente, l’autre tâche ayant été appelée' do
      flux.replace([5])
      en_erreur = tache(5 => Referentiel::Verrou::Refus.new('Référentiel refusé', nil))
      saine = tache

      passer([en_erreur, saine])

      expect(saine.numeros).to eq([5])
      expect(en_attente).to eq([5])
    end

    it 'traite une seule fois un numéro présent à la fois dans la file et dans le flux' do
      SuppressionEnAttente.create!(demarche_id: 3604, dossier: 2)
      flux.replace([2, 3])
      tache = tache()

      passer([tache])

      expect(tache.numeros).to eq([2, 3])
      expect(en_attente).to be_empty
    end

    it 'ne sauve pas le curseur quand le flux des suppressions lève' do
      allow(DossierActions).to receive(:on_deleted_dossiers).and_raise(StandardError, 'API HS')

      expect { passer([tache]) }.to raise_error(StandardError, 'API HS')

      expect(demarche.reload.checked_at).to eq(ancien_curseur)
    end

    describe 'écoute sur option (ecoute_suppressions?)' do
      let(:synchro) { BaserowSync.new(baserow: { 'table_id' => 100 }) }
      let(:coordinateur) { instance_double(MesDemarchesToBaserow::SyncCoordinator, demarche_number: 3604, delete_dossier: true) }

      before { allow(MesDemarchesToBaserow::SyncCoordinator).to receive(:new).and_return(coordinateur) }

      def enregistrer(mode, proprietaire = nil)
        ReferentielTable.create!(backend: 'baserow', table_ref: '100', mode:, proprietaire:)
      end

      it 'une synchro archive sans enregistrement : ni requête de suppression ni accès à la file, curseur avancé' do
        SuppressionEnAttente.create!(demarche_id: 3604, dossier: 9)

        passer([synchro])

        expect(DossierActions).not_to have_received(:on_deleted_dossiers)
        expect(MesDemarchesToBaserow::SyncCoordinator).not_to have_received(:new)
        expect(en_attente).to eq([9])
        expect(demarche.reload.checked_at).to be > ancien_curseur
      end

      it 'une synchro dont l\'enregistrement est archive n\'écoute pas les suppressions' do
        enregistrer('archive')

        passer([synchro])

        expect(DossierActions).not_to have_received(:on_deleted_dossiers)
      end

      it 'une synchro dont le type est encore inconnu n\'écoute pas les suppressions' do
        enregistrer('inconnu')

        passer([synchro])

        expect(DossierActions).not_to have_received(:on_deleted_dossiers)
      end

      it 'une synchro DLNUF écoute les suppressions' do
        enregistrer('dlnuf', 7)

        passer([synchro])

        expect(DossierActions).to have_received(:on_deleted_dossiers).once
        expect(coordinateur).to have_received(:delete_dossier).with(1)
        expect(coordinateur).to have_received(:delete_dossier).with(2)
      end

      it 'évalue l\'écoute après la boucle des dossiers : une table adoptée pendant le passage est écoutée' do
        allow(DossierActions).to receive(:on_dossiers) { enregistrer('dlnuf', 7) }

        passer([synchro])

        expect(DossierActions).to have_received(:on_deleted_dossiers).once
      end

      it 'un dossier supprimé par son usager sur une démarche archive ne déclenche aucun effacement' do
        dossier = double('Dossier', number: 77, date_suppression_par_usager: Time.zone.now)
        allow(DossierActions).to receive(:on_dossiers).and_yield(dossier)
        allow(service).to receive(:check_dossier)

        passer([synchro])

        expect(MesDemarchesToBaserow::SyncCoordinator).not_to have_received(:new)
        expect(service).to have_received(:check_dossier).with(demarche, dossier, [synchro])
      end
    end

    describe 'dossier supprimé par son usager seul, vu dans la boucle des dossiers' do
      let(:supprime) { double('Dossier', number: 77, date_suppression_par_usager: Time.zone.parse('2026-11-02 09:00')) }
      let(:ordinaire) { double('Dossier', number: 78, date_suppression_par_usager: nil) }
      let(:hors_filtre) do
        Class.new(ecouteuse) do
          def must_check?(_dossier) = false
        end
      end

      before do
        flux.clear
        allow(DossierActions).to receive(:on_dossiers).and_yield(supprime).and_yield(ordinaire)
      end

      it 'transmet le numéro aux tâches à l\'écoute même quand aucune tâche ne doit traiter le dossier' do
        tache = hors_filtre.new({})

        passer([tache])

        expect(tache.numeros).to eq([77])
        expect(en_attente).to be_empty
      end

      it 'appelle quand même check_dossier sur le dossier supprimé' do
        allow(service).to receive(:check_dossier)
        tache = hors_filtre.new({})

        passer([tache])

        expect(service).to have_received(:check_dossier).with(demarche, supprime, [tache])
        expect(service).to have_received(:check_dossier).with(demarche, ordinaire, [tache])
      end

      it 'met le numéro en attente quand une tâche échoue' do
        tache = hors_filtre.new({}).tap { |t| t.echecs = { 77 => Referentiel::Verrou::Refus.new('Référentiel refusé', nil) } }

        passer([tache])

        expect(en_attente).to eq([77])
      end

      it 'ne retraite pas dans le flux des suppressions un numéro déjà transmis pendant la boucle' do
        flux.replace([77, 5])
        tache = hors_filtre.new({})

        passer([tache])

        expect(tache.numeros).to eq([77, 5])
      end
    end

    describe 'file d\'attente : dossier restauré entre-temps' do
      let(:tache_ecoute) { tache }

      before { flux.clear }

      it 'retire de la file sans appeler les tâches un dossier présent et non supprimé par son usager' do
        SuppressionEnAttente.create!(demarche_id: 3604, dossier: 12)
        allow(DossierActions).to receive(:on_dossier).with(12).and_return(double('Dossier', number: 12, date_suppression_par_usager: nil))

        passer([tache_ecoute])

        expect(tache_ecoute.numeros).to be_empty
        expect(en_attente).to be_empty
      end

      it 'rejoue un numéro en attente dont le dossier est toujours supprimé par son usager' do
        SuppressionEnAttente.create!(demarche_id: 3604, dossier: 12)
        allow(DossierActions).to receive(:on_dossier).with(12)
                                                     .and_return(double('Dossier', number: 12, date_suppression_par_usager: Time.zone.now))

        passer([tache_ecoute])

        expect(tache_ecoute.numeros).to eq([12])
        expect(en_attente).to be_empty
      end

      it 'garde le numéro en file quand la lecture du dossier lève, et passe au suivant' do
        SuppressionEnAttente.create!(demarche_id: 3604, dossier: 12)
        SuppressionEnAttente.create!(demarche_id: 3604, dossier: 13)
        allow(DossierActions).to receive(:on_dossier).with(12).and_raise(StandardError, 'API HS')

        expect { passer([tache_ecoute]) }.not_to raise_error

        expect(tache_ecoute.numeros).to eq([13])
        expect(en_attente).to eq([12])
      end

      it 'ne relit pas les dossiers venus du flux du passage' do
        flux.replace([5])

        passer([tache_ecoute])

        expect(DossierActions).not_to have_received(:on_dossier)
        expect(tache_ecoute.numeros).to eq([5])
      end
    end

    describe 'un seul courriel d\'erreur par numéro' do
      before do
        allow(Rails.env).to receive(:production?).and_return(true)
        flux.replace([1])
      end

      it 'envoie le courriel au premier échec, qui met le numéro en file' do
        passer([tache(1 => StandardError.new('boum'))])

        expect(service).to have_received(:report_error).with('Error applying deleted', kind_of(StandardError)).once
        expect(en_attente).to eq([1])
      end

      it 'n\'envoie pas de courriel quand un numéro déjà en file échoue de nouveau' do
        SuppressionEnAttente.create!(demarche_id: 3604, dossier: 1)
        flux.clear

        passer([tache(1 => StandardError.new('boum'))])

        expect(service).not_to have_received(:report_error)
        expect(en_attente).to eq([1])
      end

      it 'un refus rejoué passe toujours par Alerte.signaler, sans courriel d\'erreur' do
        SuppressionEnAttente.create!(demarche_id: 3604, dossier: 1)
        flux.clear
        refus = Referentiel::Verrou::Refus.new('Référentiel refusé', nil)

        passer([tache(1 => refus)])

        expect(Referentiel::Alerte).to have_received(:signaler).with(refus)
        expect(service).not_to have_received(:report_error)
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
