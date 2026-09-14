# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SetField do
  let(:instructeur) { 'instructeur' }
  let(:demarche) { instance_double(Demarche, instructeur:) }
  let(:dossier) { double('dossier', number: 12_345, state: 'en_construction') }
  let(:task) { SetField.new(champ: 'Date limite', valeur: '2026-01-15') }

  let(:date_annotation) do
    double('DateChamp', __typename: 'DateChamp', date_value: nil)
  end

  before do
    allow(SetAnnotationValue).to receive(:set_value).and_return(true)
    allow(task).to receive(:dossier_updated)
  end

  context "quand l'annotation cible existe" do
    before { allow(task).to receive(:annotation).with('Date limite', warn_if_empty: false).and_return(date_annotation) }

    it "pose la valeur castée dans le type de l'annotation" do
      expect(SetAnnotationValue).to receive(:set_value).with(dossier, instructeur, 'Date limite', Date.new(2026, 1, 15))
      task.process(demarche, dossier)
    end
  end

  context 'avec si_vide' do
    let(:task) { SetField.new(champ: 'Date limite', valeur: '2026-01-15', si_vide: true) }

    before { allow(task).to receive(:annotation).with('Date limite', warn_if_empty: false).and_return(date_annotation) }

    it "écrit quand l'annotation est vide" do
      expect(SetAnnotationValue).to receive(:set_value)
      task.process(demarche, dossier)
    end

    context "quand l'annotation contient déjà une valeur" do
      let(:date_annotation) { double('DateChamp', __typename: 'DateChamp', date_value: '2025-12-01') }

      it "n'écrase pas la valeur existante" do
        expect(SetAnnotationValue).not_to receive(:set_value)
        task.process(demarche, dossier)
      end
    end
  end

  # L'annotation absente relève d'une erreur de configuration : on la trace dans
  # le log sans lever, sinon la tâche remonte une NoMethodError sur nil.
  context "quand l'annotation cible n'existe pas" do
    before { allow(task).to receive(:annotation).with('Date limite', warn_if_empty: false).and_return(nil) }

    it 'trace une erreur explicite et ne modifie rien' do
      expect(Rails.logger).to receive(:error).with(/l'annotation 'Date limite' n'existe pas/)
      expect(SetAnnotationValue).not_to receive(:set_value)
      expect { task.process(demarche, dossier) }.not_to raise_error
    end
  end

  # Régression : sans test d'état, la tâche s'appliquait à tous les dossiers,
  # y compris hors du périmètre déclaré par etat_du_dossier.
  context "quand l'état du dossier n'est pas dans le etat_du_dossier déclaré" do
    let(:task) { SetField.new(champ: 'Date limite', valeur: '2026-01-15', etat_du_dossier: 'en_construction') }
    let(:dossier) { double('dossier', number: 12_345, state: 'en_instruction') }

    it 'ne fait rien' do
      expect(task).not_to receive(:annotation)
      expect(SetAnnotationValue).not_to receive(:set_value)
      task.process(demarche, dossier)
    end
  end

  # Les set_field sont presque toujours imbriqués dans un conditional_field ou un
  # when_ok sans redéclarer l'état : le défaut « en_construction » des FieldChecker
  # les ferait cesser d'agir sur les dossiers en instruction ou acceptés.
  context "quand etat_du_dossier n'est pas déclaré" do
    %w[en_construction en_instruction accepte sans_suite refuse].each do |state|
      it "s'applique à un dossier #{state}" do
        dossier = double('dossier', number: 12_345, state:)
        allow(task).to receive(:annotation).with('Date limite', warn_if_empty: false).and_return(date_annotation)

        task.process(demarche, dossier)

        expect(SetAnnotationValue).to have_received(:set_value).with(dossier, instructeur, 'Date limite', Date.new(2026, 1, 15))
      end
    end
  end
end
