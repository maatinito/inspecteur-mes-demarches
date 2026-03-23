# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe DeadLineChecker do
  let(:checker) { FactoryBot.build(:dead_line_checker) }
  let(:demarche) { double('Demarche', number: 123, instructeur: 'instructeur_id') }

  def make_traitement(state, processed_at)
    double('Traitement', state: state, processed_at: processed_at.iso8601)
  end

  def make_message(created_at, date_resolution: nil)
    correction = if date_resolution
                   double('Correction', date_resolution: date_resolution.iso8601)
                 else
                   double('Correction', date_resolution: nil)
                 end
    double('Message', created_at: created_at.iso8601, correction: correction)
  end

  def make_message_without_correction(created_at)
    double('Message', created_at: created_at.iso8601, correction: nil)
  end

  def make_dossier(state:, traitements:, date_depot:, annotations: [])
    double('Dossier',
           number: 456,
           id: 'dossier_id',
           state: state,
           date_depot: date_depot.iso8601,
           traitements: traitements,
           annotations: annotations,
           champs: [])
  end

  def stub_fetch_messages(checker, messages)
    allow(checker).to receive(:fetch_dossier_messages).and_return(messages)
  end

  describe '#initialize' do
    it 'accepte recevabilite seule' do
      checker = FactoryBot.build(:dead_line_checker, :recevabilite_only)
      expect(checker.errors).to be_empty
    end

    it 'accepte instruction seule' do
      checker = FactoryBot.build(:dead_line_checker, :instruction_only)
      expect(checker.errors).to be_empty
    end

    it 'accepte les deux phases' do
      expect(checker.errors).to be_empty
    end

    it 'rejette si aucune phase configurée' do
      checker = FactoryBot.build(:dead_line_checker, :without_phases)
      expect(checker.errors).to include('Au moins une phase (recevabilite ou instruction) doit être configurée')
    end

    it 'configure les états selon les phases' do
      checker = FactoryBot.build(:dead_line_checker, :recevabilite_only)
      states = checker.instance_variable_get(:@states)
      expect(states).to include('en_construction')
      expect(states).not_to include('en_instruction')
    end
  end

  describe '#compute_instruction_days' do
    it 'calcule une période simple en instruction' do
      traitements = [make_traitement('en_instruction', 10.days.ago)]
      dossier = make_dossier(state: 'en_instruction', traitements: traitements, date_depot: 20.days.ago)

      days = checker.send(:compute_instruction_days, dossier)
      expect(days).to eq(10)
    end

    it 'calcule les allers-retours instruction/construction' do
      traitements = [
        make_traitement('en_instruction', 20.days.ago),
        make_traitement('en_construction', 15.days.ago),
        make_traitement('en_instruction', 10.days.ago)
      ]
      dossier = make_dossier(state: 'en_instruction', traitements: traitements, date_depot: 30.days.ago)

      days = checker.send(:compute_instruction_days, dossier)
      # 5 jours (20 à 15) + 10 jours (10 à now) = 15 jours
      expect(days).to eq(15)
    end

    it 'retourne 0 sans traitements en instruction' do
      traitements = [make_traitement('en_construction', 10.days.ago)]
      dossier = make_dossier(state: 'en_construction', traitements: traitements, date_depot: 20.days.ago)

      days = checker.send(:compute_instruction_days, dossier)
      expect(days).to eq(0)
    end
  end

  describe '#compute_recevabilite_days' do
    before { stub_fetch_messages(checker, messages) }

    let(:messages) { [] }

    it 'calcule la durée sans correction' do
      dossier = make_dossier(state: 'en_construction', traitements: [], date_depot: 10.days.ago)

      days = checker.send(:compute_recevabilite_days, dossier)
      expect(days).to eq(10)
    end

    context 'avec une correction résolue' do
      let(:messages) { [make_message(8.days.ago, date_resolution: 5.days.ago)] }

      it 'soustrait la période de correction' do
        dossier = make_dossier(state: 'en_construction', traitements: [], date_depot: 10.days.ago)

        days = checker.send(:compute_recevabilite_days, dossier)
        # 10 jours - 3 jours correction = 7 jours
        expect(days).to eq(7)
      end
    end

    context 'avec une correction en attente' do
      let(:messages) { [make_message(3.days.ago)] }

      it 'soustrait la période en attente' do
        dossier = make_dossier(state: 'en_construction', traitements: [], date_depot: 10.days.ago)

        days = checker.send(:compute_recevabilite_days, dossier)
        # 10 jours - 3 jours correction en attente = 7 jours
        expect(days).to eq(7)
      end
    end

    context 'avec des messages sans correction' do
      let(:messages) { [make_message_without_correction(5.days.ago)] }

      it 'ignore les messages normaux' do
        dossier = make_dossier(state: 'en_construction', traitements: [], date_depot: 10.days.ago)

        days = checker.send(:compute_recevabilite_days, dossier)
        expect(days).to eq(10)
      end
    end

    it 'ne compte pas les périodes en instruction' do
      stub_fetch_messages(checker, [])
      traitements = [
        make_traitement('en_instruction', 8.days.ago),
        make_traitement('en_construction', 5.days.ago)
      ]
      dossier = make_dossier(state: 'en_construction', traitements: traitements, date_depot: 10.days.ago)

      days = checker.send(:compute_recevabilite_days, dossier)
      # 2 jours (10 à 8) + 5 jours (5 à now) = 7 jours
      expect(days).to eq(7)
    end

    it 'gère le scénario complexe avec corrections et allers-retours' do
      traitements = [
        make_traitement('en_instruction', 25.days.ago),
        make_traitement('en_construction', 23.days.ago),
        make_traitement('en_instruction', 18.days.ago),
        make_traitement('en_construction', 15.days.ago)
      ]
      correction_messages = [
        make_message(23.days.ago, date_resolution: 20.days.ago),
        make_message(15.days.ago, date_resolution: 12.days.ago)
      ]
      stub_fetch_messages(checker, correction_messages)

      dossier = make_dossier(
        state: 'en_construction',
        traitements: traitements,
        date_depot: 30.days.ago
      )

      days = checker.send(:compute_recevabilite_days, dossier)
      # Périodes en_construction :
      #   30j→25j = 5j
      #   23j→18j = 5j (mais 3j en correction de 23j→20j)
      #   15j→now = 15j (mais 3j en correction de 15j→12j)
      # Effectif = 5 + (5-3) + (15-3) = 5 + 2 + 12 = 19 jours
      expect(days).to eq(19)
    end
  end

  describe '#process' do
    let(:checker) { FactoryBot.build(:dead_line_checker, :instruction_only) }

    before do
      allow(checker).to receive(:instructeur_id).and_return('instructeur_id')
      allow(SetAnnotationValue).to receive(:set_value)
      allow(NotificationMailer).to receive_message_chain(:with, :user_mail, :deliver_later)
      allow(ScheduledTask).to receive(:clear)
      allow(ScheduledTask).to receive(:enqueue)
    end

    it 'met à jour l\'annotation jours restants' do
      traitements = [make_traitement('en_instruction', 10.days.ago)]
      dossier = make_dossier(state: 'en_instruction', traitements: traitements, date_depot: 20.days.ago)

      checker.process(demarche, dossier)

      expect(SetAnnotationValue).to have_received(:set_value).with(
        dossier, 'instructeur_id', 'Jours restants instruction', 50
      )
    end

    it 'ne traite pas un dossier dans un état non configuré' do
      traitements = [make_traitement('en_construction', 10.days.ago)]
      dossier = make_dossier(state: 'en_construction', traitements: traitements, date_depot: 20.days.ago)

      checker.process(demarche, dossier)

      expect(SetAnnotationValue).not_to have_received(:set_value)
    end

    it 'efface le schedule existant à chaque exécution' do
      traitements = [make_traitement('en_instruction', 10.days.ago)]
      dossier = make_dossier(state: 'en_instruction', traitements: traitements, date_depot: 20.days.ago)

      checker.process(demarche, dossier)

      expect(ScheduledTask).to have_received(:clear).with(dossier: 456, task: 'dead_line_checker/456')
    end

    context 'avec seuils' do
      let(:checker) do
        FactoryBot.build(:dead_line_checker, :instruction_only, instruction: {
                           'duree_max' => 60,
                           'annotation_jours_restants' => 'Jours restants',
                           'seuils' => [
                             { 'jours' => 10, 'alerter' => 'chef@admin.gov.pf', 'objet' => 'Alerte', 'message' => 'Urgent' },
                             { 'jours' => 5, 'alerter' => 'directeur@admin.gov.pf', 'objet' => 'Critique', 'message' => 'Très urgent' }
                           ]
                         })
      end

      it 'envoie un mail quand un seuil est franchi' do
        traitements = [make_traitement('en_instruction', 55.days.ago)]
        annotation_alertes = double('Annotation', string_value: nil, label: 'Historique alertes délai')
        dossier = make_dossier(
          state: 'en_instruction', traitements: traitements, date_depot: 60.days.ago,
          annotations: [annotation_alertes]
        )

        checker.process(demarche, dossier)

        expect(NotificationMailer).to have_received(:with).at_least(:once)
      end

      it 'ne re-déclenche pas un seuil déjà déclenché' do
        traitements = [make_traitement('en_instruction', 55.days.ago)]
        annotation_alertes = double('Annotation', string_value: '10', label: 'Historique alertes délai')
        annotation_jours = double('Annotation', string_value: '5', label: 'Jours restants')
        dossier = make_dossier(
          state: 'en_instruction', traitements: traitements, date_depot: 60.days.ago,
          annotations: [annotation_alertes, annotation_jours]
        )

        checker.process(demarche, dossier)

        # Le seuil 10 ne doit pas être re-déclenché, mais le seuil 5 oui
        expect(NotificationMailer).to have_received(:with).once
      end

      it 'programme un schedule au prochain seuil non déclenché' do
        traitements = [make_traitement('en_instruction', 10.days.ago)]
        dossier = make_dossier(state: 'en_instruction', traitements: traitements, date_depot: 20.days.ago)
        # jours_restants = 60 - 10 = 50, prochain seuil = 10j → dans 40 jours

        checker.process(demarche, dossier)

        expect(ScheduledTask).to have_received(:enqueue).with(
          456, 'dead_line_checker/456', anything, anything
        )
      end

      it 'ne programme pas de schedule si tous les seuils sont déclenchés' do
        traitements = [make_traitement('en_instruction', 58.days.ago)]
        annotation_alertes = double('Annotation', string_value: '10, 5', label: 'Historique alertes délai')
        dossier = make_dossier(
          state: 'en_instruction', traitements: traitements, date_depot: 60.days.ago,
          annotations: [annotation_alertes]
        )

        checker.process(demarche, dossier)

        expect(ScheduledTask).not_to have_received(:enqueue)
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
