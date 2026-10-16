# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe Dbs::SuiviCarnet do
  include ActiveSupport::Testing::TimeHelpers

  let(:params) do
    { j0: "Date de début d'isolement (J0)", recu: 'Effectif reçu', prefixe_jour: 'Morts du jour',
      alertes: 'Alertes mortalité', relance: 'Relance silence', dernier_jour: 'Dernier jour saisi',
      mortalite: 'Mortalité sur 3 jours (%)', destinataires_alerte: 'cellule@exemple.pf',
      objet_alerte: 'Mortalité J{jour}', message_alerte: '{morts} morts / {restant}', message_relance: 'Saisir {jours_a_saisir}',
      nb_jours: 30, prolongation_usager: 'Durée de prolongation (jours)', prolongation_accordee: 'Prolongation totale (jours)',
      ecart_signale: 'Écart prolongation signalé', destinataires_veterinaire: 'veto@exemple.pf', message_ecart: '{saisi}/{accorde}' }
  end
  let(:task) { described_class.new(params) }
  let(:demarche) { instance_double(Demarche, instructeur: 'robot') }
  let(:morts) { [10, 30] }
  let(:trace) do
    { 'Alertes mortalité' => nil, 'Relance silence' => nil, 'Écart prolongation signalé' => nil,
      'Prolongation totale (jours)' => nil }
  end
  let(:etat) { 'en_construction' }

  # Comme l'API : int_value arrive en chaîne ("5000").
  def int(label, val) = double(label, label:, __typename: 'IntegerNumberChamp', int_value: val&.to_s, string_value: val&.to_s)
  def txt(label, val) = double(label, label:, __typename: 'TextChamp', value: val, string_value: val)

  let(:dossier) do
    jours = (1..30).map { |n| int("Morts du jour #{n}", morts[n - 1]) }
    j0 = double('J0', label: "Date de début d'isolement (J0)", __typename: 'DateChamp', date_value: '2026-10-01',
                      string_value: '1 octobre 2026')
    double('Carnet', number: 700_001, state: etat,
                     champs: [j0, int('Effectif reçu', 1000), int('Durée de prolongation (jours)', nil), *jours],
                     annotations: trace.map { |k, v| k.include?('Prolongation') ? int(k, v) : txt(k, v) })
  end

  before do
    allow(SetAnnotationValue).to receive(:set_value).and_return(true)
    allow(SendMessage).to receive(:deliver_message).and_return(true)
    allow(NotificationMailer).to receive(:with).and_return(double('M', user_mail: double('D', deliver_later: true)))
    allow(ScheduledTask).to receive(:enqueue)
    allow(ScheduledTask).to receive(:clear)
    travel_to Time.zone.local(2026, 10, 3, 9, 0) # jour de suivi 2
  end

  after { travel_back }

  it 'alerte la cellule pour J2 (30 ≥ 3 % de 990) et trace le jour' do
    task.process(demarche, dossier)
    expect(NotificationMailer).to have_received(:with).with(subject: 'Mortalité J2', message: '30 morts / 990',
                                                            recipients: 'cellule@exemple.pf')
    expect(SetAnnotationValue).to have_received(:set_value).with(dossier, 'robot', 'Alertes mortalité', 'J2')
  end

  context 'J2 déjà signalé' do
    let(:trace) { super().merge('Alertes mortalité' => 'J2') }

    it 'ne réalerte pas' do
      task.process(demarche, dossier)
      expect(NotificationMailer).not_to have_received(:with)
    end
  end

  it 'écrit le tableau de bord et replanifie au lendemain 7 h' do
    task.process(demarche, dossier)
    expect(SetAnnotationValue).to have_received(:set_value).with(dossier, 'robot', 'Dernier jour saisi', 2)
    expect(SetAnnotationValue).to have_received(:set_value).with(dossier, 'robot', 'Mortalité sur 3 jours (%)', 4.0)
    expect(ScheduledTask).to have_received(:enqueue).with(700_001, 'dbs/suivi_carnet/700001', anything,
                                                          Time.zone.local(2026, 10, 4, 7))
  end

  context 'silence de 4 jours' do
    let(:morts) { [1] }

    before { travel_to Time.zone.local(2026, 10, 6, 9, 0) } # jour 5, dernier saisi 1

    it "relance l'éleveur une fois par silence" do
      task.process(demarche, dossier)
      expect(SendMessage).to have_received(:deliver_message).with(dossier, 'robot', 'Saisir 2, 3, 4, 5')
      expect(SetAnnotationValue).to have_received(:set_value).with(dossier, 'robot', 'Relance silence', '1')
    end

    context 'déjà relancé pour ce silence' do
      let(:trace) { super().merge('Relance silence' => '1') }

      it 'ne relance pas' do
        task.process(demarche, dossier)
        expect(SendMessage).not_to have_received(:deliver_message)
      end
    end
  end

  context 'au-delà de la période (jour 25)' do
    let(:morts) { [0] * 21 }

    before { travel_to Time.zone.local(2026, 10, 26, 9, 0) }

    it 'ne relance pas des jours non prévus quand rien n a été prolongé' do
      task.process(demarche, dossier)
      expect(SendMessage).not_to have_received(:deliver_message)
    end

    context 'avec une prolongation accordée de 10 jours' do
      let(:trace) { super().merge('Prolongation totale (jours)' => 10, 'Écart prolongation signalé' => '0/10 signalé le 20/10/2026') }

      it 'relance les jours prolongés' do
        task.process(demarche, dossier)
        expect(SendMessage).to have_received(:deliver_message).with(dossier, 'robot', 'Saisir 22, 23, 24, 25')
      end
    end
  end

  context "quand l'écriture d'une trace échoue après un envoi" do
    let(:morts) { [1] }

    before do
      travel_to Time.zone.local(2026, 10, 6, 9, 0)
      allow(SetAnnotationValue).to receive(:set_value).and_raise('boom')
    end

    it 'a déjà replanifié au lendemain : pas de nouvel essai à la minute' do
      expect { task.process(demarche, dossier) }.to raise_error('boom')
      expect(ScheduledTask).to have_received(:enqueue).with(700_001, 'dbs/suivi_carnet/700001', anything,
                                                            Time.zone.local(2026, 10, 7, 7))
    end
  end

  context 'jour à 0 mort' do
    let(:morts) { [0, 0, 0, 0, 0] }

    before { travel_to Time.zone.local(2026, 10, 6, 9, 0) }

    it 'ne relance pas (0 est une saisie)' do
      task.process(demarche, dossier)
      expect(SendMessage).not_to have_received(:deliver_message)
      expect(NotificationMailer).not_to have_received(:with)
    end
  end

  context 'écart de prolongation' do
    let(:trace) { super().merge('Prolongation totale (jours)' => 10, 'Alertes mortalité' => 'J2') }

    it "le note sans prévenir le jour où il apparaît (l'éleveur n'a pas encore lu le compte rendu)" do
      task.process(demarche, dossier)
      expect(NotificationMailer).not_to have_received(:with)
      expect(SetAnnotationValue).to have_received(:set_value).with(dossier, 'robot', 'Écart prolongation signalé',
                                                                   '0/10 vu le 03/10/2026')
    end

    context 'vu depuis 1 jour seulement' do
      let(:trace) { super().merge('Écart prolongation signalé' => '0/10 vu le 02/10/2026') }

      it 'attend encore' do
        task.process(demarche, dossier)
        expect(NotificationMailer).not_to have_received(:with)
      end
    end

    context 'toujours là 2 jours plus tard' do
      let(:trace) { super().merge('Écart prolongation signalé' => '0/10 vu le 01/10/2026') }

      it 'prévient la vétérinaire et le trace' do
        task.process(demarche, dossier)
        expect(NotificationMailer).to have_received(:with).with(hash_including(recipients: 'veto@exemple.pf', message: '0/10'))
        expect(SetAnnotationValue).to have_received(:set_value).with(dossier, 'robot', 'Écart prolongation signalé',
                                                                     '0/10 signalé le 03/10/2026')
      end
    end

    context 'déjà signalé' do
      let(:trace) { super().merge('Écart prolongation signalé' => '0/10 signalé le 02/10/2026') }

      it 'ne reprévient pas' do
        task.process(demarche, dossier)
        expect(NotificationMailer).not_to have_received(:with)
      end
    end

    context 'un autre écart apparaît (nouvelle prolongation)' do
      let(:trace) do
        super().merge('Prolongation totale (jours)' => 15, 'Écart prolongation signalé' => '0/10 signalé le 01/10/2026')
      end

      it 'repart de zéro' do
        task.process(demarche, dossier)
        expect(NotificationMailer).not_to have_received(:with)
        expect(SetAnnotationValue).to have_received(:set_value).with(dossier, 'robot', 'Écart prolongation signalé',
                                                                     '0/15 vu le 03/10/2026')
      end
    end
  end

  context 'carnet clos' do
    let(:etat) { 'accepte' }

    it "n'envoie rien et ne replanifie pas" do
      task.process(demarche, dossier)
      expect(NotificationMailer).not_to have_received(:with)
      expect(ScheduledTask).not_to have_received(:enqueue)
      expect(ScheduledTask).to have_received(:clear).with(task: 'dbs/suivi_carnet/700001', dossier: 700_001)
    end
  end
end
# rubocop:enable Metrics/BlockLength
