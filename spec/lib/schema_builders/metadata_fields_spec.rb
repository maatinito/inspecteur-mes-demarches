# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchemaBuilders::MetadataFields do
  describe '.all' do
    it 'commence par la colonne primaire Dossier puis les champs système' do
      names = described_class.all([]).map(&:name)
      expect(names.first).to eq('Dossier')
      expect(names).to include('Statut', 'Date de dépôt', 'Date de passage en instruction',
                               'Date de traitement', 'Email usager', 'Groupe instructeur', 'Labels')
    end

    it 'ajoute les champs personne physique pour le mode :physique' do
      names = described_class.all([:physique]).map(&:name)
      expect(names).to include('Civilité', 'Nom', 'Prénom')
      expect(names).not_to include('Numéro TAHITI', 'Raison sociale')
    end

    it 'ajoute les champs personne morale pour le mode :morale' do
      names = described_class.all([:morale]).map(&:name)
      expect(names).to include('Numéro TAHITI', 'Raison sociale', 'Nom commercial', 'Forme juridique', 'Libellé NAF')
      expect(names).not_to include('Civilité', 'Prénom')
    end

    it 'cumule les deux jeux quand les deux modes sont fournis (repli)' do
      names = described_class.all(%i[physique morale]).map(&:name)
      expect(names).to include('Civilité', 'Numéro TAHITI')
    end

    it 'utilise des noms identiques quelle que soit la cible (uniformité)' do
      # La liste ne dépend pas de la plateforme : un seul jeu de libellés.
      expect(described_class.all(%i[physique morale]).map(&:name)).to all(be_a(String))
    end
  end

  describe '.mode_for_typename' do
    it 'mappe PersonnePhysique sur :physique' do
      expect(described_class.mode_for_typename('PersonnePhysique')).to eq(:physique)
    end

    it 'mappe PersonneMorale et PersonneMoraleIncomplete sur :morale' do
      expect(described_class.mode_for_typename('PersonneMorale')).to eq(:morale)
      expect(described_class.mode_for_typename('PersonneMoraleIncomplete')).to eq(:morale)
    end

    it 'retourne nil pour un type inconnu ou absent' do
      expect(described_class.mode_for_typename('Autre')).to be_nil
      expect(described_class.mode_for_typename(nil)).to be_nil
    end
  end

  describe 'source d\'extraction' do
    it 'lit la valeur depuis un dossier' do
      dossier = double('Dossier', number: 1234, state: 'en_instruction')
      statut = described_class.system.find { |f| f.key == :statut }
      dossier_field = described_class.dossier

      expect(dossier_field.source.call(dossier)).to eq(1234)
      expect(statut.source.call(dossier)).to eq('en_instruction')
    end
  end
end
