# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VerificationService do
  let(:service) { VerificationService.new }

  describe '.retry_reference_time' do
    it 'returns BOOT_TIME when it is after last 8am' do
      boot_time = VerificationService::BOOT_TIME
      last_8am = Time.current.change(hour: 8)
      last_8am -= 1.day if last_8am > Time.current

      result = VerificationService.retry_reference_time
      expect(result).to eq([boot_time, last_8am].max)
    end

    it 'returns a time that is not in the future' do
      expect(VerificationService.retry_reference_time).to be <= Time.current
    end
  end

  describe '.procedures' do
    it 'ne garde que les blocs Hash possédant une clé demarches' do
      data = {
        'entree' => { 'demarches' => [3602], 'when_ok' => [] },
        'template' => { 'champs' => [] }
      }
      expect(VerificationService.procedures(data).keys).to eq(['entree'])
    end

    it 'ignore sans planter les valeurs racine non-Hash (ancre liste, scalaire)' do
      data = {
        'etat_remplissage_carte' => %w[en_construction en_instruction],
        'version' => 3,
        'entree' => { 'demarches' => [3602] }
      }
      expect { VerificationService.procedures(data) }.not_to raise_error
      expect(VerificationService.procedures(data).keys).to eq(['entree'])
    end
  end

  describe '#when_ok' do
    let(:md_dossier) { double('md_dossier', number: 123) }
    let(:check) do
      instance_double('Check', :failed= => false, :failed_at= => nil, failed: false, update: true)
    end

    before do
      allow(Check).to receive(:find_or_create_by).and_return(check)
    end

    it 'ne plante pas quand le rechargement du dossier échoue entre deux tâches (on_dossier => nil)' do
      task1 = double('task1', name: 't1', version: 1, valid?: true, process: nil)
      task2 = double('task2', name: 't2', version: 1, valid?: true, process: nil)
      allow(task1).to receive(:dossier_updated?).and_return(true)
      allow(task2).to receive(:dossier_updated?).and_return(false)

      service.instance_variable_set(:@ok_tasks, [task1, task2])
      # Le rechargement GraphQL renvoie nil (erreur API transitoire).
      allow(DossierActions).to receive(:on_dossier).and_return(nil)

      expect do
        service.send(:when_ok, 'demarche', md_dossier, [])
      end.not_to raise_error

      # La 2e tâche est tout de même traitée malgré l'échec du rechargement.
      expect(task2).to have_received(:process)
    end

    it 'un refus de référentiel marque le contrôle en échec et alerte, sans courriel par dossier ni exception' do
      refus = Referentiel::Verrou::Refus.new('Référentiel refusé', nil)
      task = double('task', name: 't1', version: 1, valid?: true, dossier_updated?: false)
      allow(task).to receive(:process).and_raise(refus)
      allow(Referentiel::Alerte).to receive(:signaler)
      allow(service).to receive(:report_error)
      service.instance_variable_set(:@ok_tasks, [task])

      dossiers = [double('md_dossier', number: 123), double('md_dossier', number: 124)]
      expect do
        dossiers.each { |dossier| service.send(:when_ok, 'demarche', dossier, []) }
      end.not_to raise_error

      expect(check).to have_received(:failed=).with(true).twice
      expect(check).to have_received(:failed_at=).with(kind_of(Time)).twice
      expect(Referentiel::Alerte).to have_received(:signaler).with(refus).twice
      expect(service).not_to have_received(:report_error)
    end
  end

  describe '#report_error' do
    let(:mailer_double) { double('NotificationMailer') }
    let(:exception) { StandardError.new('Something went wrong') }

    before do
      allow(NotificationMailer).to receive(:with).and_return(mailer_double)
      allow(mailer_double).to receive(:report_error).and_return(mailer_double)
      allow(mailer_double).to receive(:deliver_later)
    end

    it 'sends notification' do
      service.report_error('Error', exception)

      expect(NotificationMailer).to have_received(:with)
      expect(mailer_double).to have_received(:deliver_later)
    end
  end
end
