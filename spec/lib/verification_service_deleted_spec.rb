# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VerificationService do
  let(:service) { VerificationService.new }

  describe '#check_demarche (hook deleted)' do
    let(:demarche) { instance_double(Demarche, id: 3604, checked_at: Time.zone.parse('2026-11-01'), :checked_at= => nil, save: true) }
    let(:ecouteuse) do
      Class.new(InspectorTask) do
        attr_reader :appels

        def deleted(demarche, number)
          (@appels ||= []) << [demarche, number]
          raise @erreur if @erreur && number == 1

          nil
        end

        def raise_on_first(erreur)
          @erreur = erreur
        end
      end
    end

    before do
      allow(DemarcheActions).to receive(:get_demarche).and_return(demarche)
      allow(DossierActions).to receive(:on_dossiers)
      allow(DossierActions).to receive(:on_deleted_dossiers).and_yield(1).and_yield(2)
      allow(service).to receive(:current_user_has_access_to?).and_return(true)
      allow(service).to receive(:report_error)
      service.instance_variable_set(:@ok_tasks, [])
    end

    it "n'interroge pas les suppressions quand aucune tâche ne les écoute" do
      service.send(:check_demarche, [InspectorTask.new({})], 3604, false, 'conf')

      expect(DossierActions).not_to have_received(:on_deleted_dossiers)
      expect(demarche).to have_received(:save)
    end

    it 'appelle deleted sur chaque tâche qui le surcharge, avec le curseur de la démarche' do
      tache = ecouteuse.new({})
      ok = ecouteuse.new({})
      service.instance_variable_set(:@ok_tasks, [ok])

      service.send(:check_demarche, [tache, InspectorTask.new({})], 3604, false, 'conf')

      expect(DossierActions).to have_received(:on_deleted_dossiers).once.with(3604, demarche.checked_at)
      expect(tache.appels).to eq([[demarche, 1], [demarche, 2]])
      expect(ok.appels).to eq([[demarche, 1], [demarche, 2]])
    end

    it 'continue après une tâche en erreur et avance le curseur' do
      en_erreur = ecouteuse.new({})
      en_erreur.raise_on_first(StandardError.new('boum'))
      suivante = ecouteuse.new({})
      allow(Rails.env).to receive(:production?).and_return(true)

      expect { service.send(:check_demarche, [en_erreur, suivante], 3604, false, 'conf') }.not_to raise_error

      expect(service).to have_received(:report_error).with('Error applying deleted', kind_of(StandardError)).once
      expect(en_erreur.appels.map(&:last)).to eq([1, 2])
      expect(suivante.appels.map(&:last)).to eq([1, 2])
      expect(demarche).to have_received(:checked_at=)
      expect(demarche).to have_received(:save)
    end

    it 'alerte sans lever quand une tâche refuse' do
      refus = Referentiel::Verrou::Refus.new('Référentiel refusé', nil)
      tache = ecouteuse.new({})
      tache.raise_on_first(refus)
      allow(Referentiel::Alerte).to receive(:signaler)

      expect { service.send(:check_demarche, [tache], 3604, false, 'conf') }.not_to raise_error

      expect(Referentiel::Alerte).to have_received(:signaler).with(refus)
      expect(service).not_to have_received(:report_error)
      expect(tache.appels.map(&:last)).to eq([1, 2])
    end
  end
end
