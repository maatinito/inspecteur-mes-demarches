# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScheduledTaskJob do
  describe '#task_class_name' do
    subject(:job) { described_class.new }

    it 'retire l identifiant de dossier ajouté par DeadLineChecker' do
      expect(job.send(:task_class_name, 'dead_line_checker/679212')).to eq 'dead_line_checker'
    end

    it 'retire l identifiant ajouté par Schedule' do
      expect(job.send(:task_class_name, 'schedule/rappel_1')).to eq 'schedule'
    end

    it 'garde intact un nom de classe namespacé' do
      expect(job.send(:task_class_name, 'payzen/payment_order')).to eq 'payzen/payment_order'
    end

    it 'garde intact un nom sans identifiant' do
      expect(job.send(:task_class_name, 'dead_line_checker')).to eq 'dead_line_checker'
    end
  end

  describe '#perform' do
    let(:demarche) { create(:demarche, id: 3899) }
    let(:dossier) { double('Dossier', number: 679_212, demarche: double('DemarcheGql', number: 3899)) }
    let(:parameters) { { 'annotation_alertes' => 'Alertes délai', 'instruction' => { 'duree_max' => 0, 'seuils' => [] } } }

    before do
      demarche
      ScheduledTask.create!(dossier: 679_212, task: 'dead_line_checker/679212', parameters: parameters.to_json, run_at: 1.minute.ago)
      allow(DossierActions).to receive(:on_dossier).with(679_212).and_yield(dossier)
      allow_any_instance_of(DeadLineChecker).to receive(:process)
      allow(NotificationMailer).to receive(:with).and_call_original
    end

    it 'rejoue une tâche dead_line_checker enregistrée avec son numéro de dossier, puis la supprime' do
      expect_any_instance_of(DeadLineChecker).to receive(:process).with(demarche, dossier)
      described_class.perform_now
      expect(ScheduledTask.where(dossier: 679_212)).to be_empty
      expect(NotificationMailer).not_to have_received(:with).with(hash_including(message: a_string_matching(/Error processing/)))
    end
  end
end
