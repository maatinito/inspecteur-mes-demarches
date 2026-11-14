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
  end
end
# rubocop:enable Metrics/BlockLength
