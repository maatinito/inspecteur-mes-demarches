# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GenerateId do
  let(:instructeur_id) { 'instructeur-123' }
  let(:demarche) do
    double('demarche', instructeur: instructeur_id)
  end

  let(:annotation) do
    double('annotation',
           id: 'annotation-456',
           label: 'Identifiant du permis',
           __typename: 'TextChamp')
  end

  let(:dossier) do
    double('dossier',
           id: 'dossier-789',
           number: 12_345,
           state: 'en_construction',
           champs: [],
           annotations: [annotation])
  end

  describe '#process' do
    before do
      allow(SetAnnotationValue).to receive(:value_of).and_return(current_value)
      allow(SetAnnotationValue).to receive(:raw_set_value)
    end

    context 'when annotation is empty' do
      let(:current_value) { nil }
      let(:params) { { champ: 'Identifiant du permis' } }
      let(:checker) { described_class.new(params) }

      before do
        allow(checker).to receive(:param_annotation).with(:champ, warn_if_empty: true).and_return(annotation)
        allow(checker).to receive(:instructeur_id).and_return(instructeur_id)
      end

      it 'generates a new ID' do
        checker.process(demarche, dossier)

        expect(SetAnnotationValue).to have_received(:raw_set_value)
          .with(dossier.id, instructeur_id, annotation.id, anything)
      end

      it 'generates a valid UUID v7 format (32 hex chars)' do
        allow(SetAnnotationValue).to receive(:raw_set_value) do |_, _, _, value|
          expect(value).to match(/^[0-9a-f]{32}$/)
        end

        checker.process(demarche, dossier)
      end

      it 'marks dossier as updated' do
        checker.process(demarche, dossier)

        expect(checker.updated_dossiers).to include(dossier.number)
      end
    end

    context 'when annotation already has a value' do
      let(:current_value) { '018d3b8a01234567abcdef0123456789' }
      let(:params) { { champ: 'Identifiant du permis' } }
      let(:checker) { described_class.new(params) }

      before do
        allow(checker).to receive(:param_annotation).with(:champ, warn_if_empty: true).and_return(annotation)
      end

      it 'does not overwrite existing ID' do
        checker.process(demarche, dossier)

        expect(SetAnnotationValue).not_to have_received(:raw_set_value)
      end

      it 'does not mark dossier as updated' do
        checker.process(demarche, dossier)

        expect(checker.updated_dossiers).to be_empty
      end
    end

    context 'with custom timestamp field' do
      let(:current_value) { nil }
      let(:params) do
        {
          champ: 'Identifiant du permis',
          timestamp_field: 'date_depot'
        }
      end
      let(:checker) { described_class.new(params) }

      let(:deposited_at) { Time.parse('2024-01-15 10:30:00 UTC') }

      before do
        allow(checker).to receive(:param_annotation).with(:champ, warn_if_empty: true).and_return(annotation)
        allow(checker).to receive(:instructeur_id).and_return(instructeur_id)
        allow(checker).to receive(:object_field_values)
          .with(dossier, 'date_depot', log_empty: false)
          .and_return([deposited_at])
      end

      it 'generates ID based on custom timestamp' do
        # Extraire le timestamp de l'UUID généré et vérifier qu'il correspond
        allow(SetAnnotationValue).to receive(:raw_set_value) do |_, _, _, value|
          # Les 12 premiers caractères hex encodent le timestamp (48 bits)
          timestamp_hex = value[0..11]
          timestamp_ms = timestamp_hex.to_i(16)
          timestamp_from_id = Time.at(timestamp_ms / 1000.0)

          # Vérifier que le timestamp est proche (dans la même seconde)
          expect(timestamp_from_id.to_i).to eq(deposited_at.to_i)
        end

        checker.process(demarche, dossier)
      end

      it 'generates sortable IDs' do
        id1 = nil
        id2 = nil

        # Premier ID avec le timestamp de dépôt
        allow(SetAnnotationValue).to receive(:raw_set_value) do |_, _, _, value|
          id1 = value
        end
        checker.process(demarche, dossier)

        # Deuxième ID avec un timestamp plus récent
        later_time = deposited_at + 3600 # 1 heure plus tard
        allow(checker).to receive(:object_field_values)
          .with(dossier, 'date_depot', log_empty: false)
          .and_return([later_time])
        allow(SetAnnotationValue).to receive(:value_of).and_return(nil)

        allow(SetAnnotationValue).to receive(:raw_set_value) do |_, _, _, value|
          id2 = value
        end
        checker.process(demarche, dossier)

        # Les IDs doivent être triables chronologiquement
        expect(id1).to be < id2
      end
    end

    context 'when annotation is not found' do
      let(:current_value) { nil }
      let(:params) { { champ: 'Champ inexistant' } }
      let(:checker) { described_class.new(params) }

      before do
        allow(checker).to receive(:param_annotation).with(:champ, warn_if_empty: true).and_return(nil)
      end

      it 'does not generate ID' do
        checker.process(demarche, dossier)

        expect(SetAnnotationValue).not_to have_received(:raw_set_value)
      end

      it 'logs a warning' do
        expect(Rails.logger).to receive(:warn).with(/Annotation .* introuvable/)
        checker.process(demarche, dossier)
      end
    end

    context 'when dossier state does not match' do
      let(:current_value) { nil }
      let(:params) do
        {
          champ: 'Identifiant du permis',
          etat_du_dossier: ['en_instruction']
        }
      end
      let(:checker) { described_class.new(params) }

      before do
        allow(dossier).to receive(:state).and_return('en_construction')
      end

      it 'does not generate ID' do
        checker.process(demarche, dossier)

        expect(SetAnnotationValue).not_to have_received(:raw_set_value)
      end
    end
  end

  describe 'UUID v7 properties' do
    let(:checker) { described_class.new({ champ: 'test' }) }

    it 'generates IDs that are sortable chronologically' do
      timestamp1 = Time.parse('2024-01-01 10:00:00')
      timestamp2 = Time.parse('2024-01-01 10:00:01')

      checker.send(:generate_id_with_timestamp).tap do
        allow(checker).to receive(:extract_timestamp).and_return(timestamp1)
      end

      checker.send(:generate_id_with_timestamp).tap do
        allow(checker).to receive(:extract_timestamp).and_return(timestamp2)
      end

      # Régénérer proprement avec les timestamps
      allow(checker).to receive(:extract_timestamp).and_return(timestamp1)
      id1 = checker.send(:generate_id_with_timestamp)

      allow(checker).to receive(:extract_timestamp).and_return(timestamp2)
      id2 = checker.send(:generate_id_with_timestamp)

      expect(id1).to be < id2
    end

    it 'generates IDs of 32 characters' do
      id = checker.send(:generate_id_with_timestamp)
      expect(id.length).to eq(32)
    end

    it 'generates IDs with valid hexadecimal characters' do
      id = checker.send(:generate_id_with_timestamp)
      expect(id).to match(/^[0-9a-f]{32}$/)
    end

    it 'generates consistent timestamp prefix for same time' do
      timestamp = Time.parse('2024-01-15 10:30:00 UTC')
      allow(checker).to receive(:extract_timestamp).and_return(timestamp)

      id1 = checker.send(:generate_id_with_timestamp)
      id2 = checker.send(:generate_id_with_timestamp)

      # Les 12 premiers caractères (48 bits timestamp) doivent être identiques
      expect(id1[0..11]).to eq(id2[0..11])
    end

    it 'has version bits set to 7' do
      id = checker.send(:generate_id_with_timestamp)

      # Structure UUID v7 compact (32 chars sans tirets) :
      # 0-7: time_high (8 chars)
      # 8-11: time_low (4 chars)
      # 12-15: rand_a avec version (4 chars) ← version ici
      # 16-19: rand_b high avec variant (4 chars)
      # 20-31: rand_b low (12 chars)

      # Le 13ème caractère (position 12) contient la version dans ses 4 bits de poids fort
      version_char = id[12]
      expect(version_char).to eq('7')
    end
  end
end
