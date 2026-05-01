# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe MesDemarchesToBaserow::DataExtractor do
  let(:field_metadata) do
    {
      'Nom' => { 'type' => 'text', 'id' => 1 },
      'Email' => { 'type' => 'email', 'id' => 2 },
      'Date de naissance' => { 'type' => 'date', 'id' => 3 },
      'Accepte conditions' => { 'type' => 'boolean', 'id' => 4 },
      'Documents' => { 'type' => 'file', 'id' => 5 }
    }
  end

  let(:options) do
    {
      'include_system_fields' => true,
      'include_annotations' => true
    }
  end

  let(:extractor) { described_class.new(field_metadata, options) }

  describe '#normalize_files' do
    let(:file1) { double('File', filename: 'doc1.pdf', url: 'https://example.com/doc1.pdf', byte_size: 1024) }
    let(:file2) { double('File', filename: 'doc2.pdf', url: 'https://example.com/doc2.pdf', byte_size: 2048) }
    let(:file3) { double('File', filename: 'doc3.pdf', url: 'https://example.com/doc3.pdf', byte_size: 3072) }

    let(:champ) { double('PieceJustificativeChamp', files: [file1, file2, file3], label: 'Pièces jointes', __typename: 'PieceJustificativeChamp') }

    context 'quand il n\'y a pas de fichiers existants' do
      it 'retourne tous les fichiers comme nouveaux (avec url)' do
        result = extractor.send(:normalize_files, champ, [])

        expect(result).to contain_exactly(
          { url: 'https://example.com/doc1.pdf', visible_name: 'doc1.pdf' },
          { url: 'https://example.com/doc2.pdf', visible_name: 'doc2.pdf' },
          { url: 'https://example.com/doc3.pdf', visible_name: 'doc3.pdf' }
        )
      end
    end

    context 'quand certains fichiers existent déjà (même nom et taille)' do
      let(:existing_files) do
        [
          { 'name' => 'baserow_hash_123', 'visible_name' => 'doc1.pdf', 'url' => 'https://baserow.com/files/123', 'size' => 1024 },
          { 'name' => 'baserow_hash_124', 'visible_name' => 'doc2.pdf', 'url' => 'https://baserow.com/files/124', 'size' => 2048 }
        ]
      end

      it 'retourne tous les fichiers (existants réutilisés + nouveaux)' do
        result = extractor.send(:normalize_files, champ, existing_files)

        expect(result).to contain_exactly(
          { 'name' => 'baserow_hash_123', 'visible_name' => 'doc1.pdf' },
          { 'name' => 'baserow_hash_124', 'visible_name' => 'doc2.pdf' },
          { url: 'https://example.com/doc3.pdf', visible_name: 'doc3.pdf' }
        )
      end
    end

    context 'quand un fichier a le même nom mais une taille différente' do
      let(:existing_files) do
        [
          { 'name' => 'baserow_hash_123', 'visible_name' => 'doc1.pdf', 'url' => 'https://baserow.com/files/123', 'size' => 9999 }
        ]
      end

      it 'considère le fichier comme nouveau (taille différente)' do
        result = extractor.send(:normalize_files, champ, existing_files)

        # Tous les fichiers sont nouveaux car aucun ne matche la signature (nom + taille)
        expect(result).to contain_exactly(
          { url: 'https://example.com/doc1.pdf', visible_name: 'doc1.pdf' },
          { url: 'https://example.com/doc2.pdf', visible_name: 'doc2.pdf' },
          { url: 'https://example.com/doc3.pdf', visible_name: 'doc3.pdf' }
        )
      end
    end

    context 'quand tous les fichiers existent déjà (même nom et taille)' do
      let(:existing_files) do
        [
          { 'name' => 'baserow_hash_123', 'visible_name' => 'doc1.pdf', 'url' => 'https://baserow.com/files/123', 'size' => 1024 },
          { 'name' => 'baserow_hash_124', 'visible_name' => 'doc2.pdf', 'url' => 'https://baserow.com/files/124', 'size' => 2048 },
          { 'name' => 'baserow_hash_125', 'visible_name' => 'doc3.pdf', 'url' => 'https://baserow.com/files/125', 'size' => 3072 }
        ]
      end

      it 'retourne tous les fichiers existants réutilisés (pas de nouveaux uploads)' do
        result = extractor.send(:normalize_files, champ, existing_files)

        expect(result).to contain_exactly(
          { 'name' => 'baserow_hash_123', 'visible_name' => 'doc1.pdf' },
          { 'name' => 'baserow_hash_124', 'visible_name' => 'doc2.pdf' },
          { 'name' => 'baserow_hash_125', 'visible_name' => 'doc3.pdf' }
        )
      end
    end

    context 'quand le champ n\'a pas de fichiers' do
      let(:champ) { double('PieceJustificativeChamp', files: [], label: 'Pièces jointes', __typename: 'PieceJustificativeChamp') }

      it 'retourne les fichiers existants' do
        existing_files = [
          { 'name' => 'doc1.pdf', 'url' => 'https://baserow.com/files/123', 'size' => 1024 }
        ]

        result = extractor.send(:normalize_files, champ, existing_files)

        expect(result).to eq(existing_files)
      end
    end

    context 'quand le champ MD n\'est pas un PieceJustificativeChamp' do
      let(:text_champ) { double('TextChamp', label: 'Documents', __typename: 'TextChamp', value: 'some text') }

      it 'retourne les fichiers existants sans erreur' do
        existing_files = [
          { 'name' => 'doc1.pdf', 'url' => 'https://baserow.com/files/123', 'size' => 1024 }
        ]

        result = extractor.send(:normalize_files, text_champ, existing_files)

        expect(result).to eq(existing_files)
      end
    end
  end

  describe '#normalize_phone' do
    it 'formate un numéro international avec texte parasite' do
      result = extractor.send(:normalize_phone, '+33766616250 (réside en métropole)')
      expect(result).to eq('+33 7 66 61 62 50')
    end

    it 'formate un numéro local PF' do
      result = extractor.send(:normalize_phone, '87123456')
      expect(result).to eq('+689 87 12 34 56')
    end

    it 'retourne nil pour une valeur vide' do
      expect(extractor.send(:normalize_phone, '')).to be_nil
      expect(extractor.send(:normalize_phone, nil)).to be_nil
    end

    it 'nettoie une valeur non reconnue comme numéro' do
      result = extractor.send(:normalize_phone, 'pas de téléphone')
      expect(result).to eq('')
    end
  end

  describe '#format_date' do
    it 'convertit une date ISO8601 correctement' do
      date_string = '2024-01-15T14:30:00+00:00'
      result = extractor.send(:format_date, date_string)

      expect(result).to eq('2024-01-15')
    end

    it 'retourne nil pour une date vide' do
      expect(extractor.send(:format_date, '')).to be_nil
      expect(extractor.send(:format_date, nil)).to be_nil
    end

    it 'retourne nil pour une date invalide' do
      expect(extractor.send(:format_date, 'invalid')).to be_nil
    end
  end

  describe '#normalize_boolean' do
    it 'convertit "Oui" en true' do
      expect(extractor.send(:normalize_boolean, 'Oui')).to be true
      expect(extractor.send(:normalize_boolean, 'oui')).to be true
    end

    it 'convertit "Non" en false' do
      expect(extractor.send(:normalize_boolean, 'Non')).to be false
      expect(extractor.send(:normalize_boolean, 'non')).to be false
    end

    it 'retourne nil pour une valeur vide' do
      expect(extractor.send(:normalize_boolean, '')).to be_nil
      expect(extractor.send(:normalize_boolean, nil)).to be_nil
    end
  end

  describe '#normalize_number' do
    it 'convertit un string en nombre' do
      champ = double('IntegerNumberChamp', __typename: 'IntegerNumberChamp', string_value: '42')
      expect(extractor.send(:normalize_number, champ)).to eq(42)
    end

    it 'convertit un décimal' do
      champ = double('DecimalNumberChamp', __typename: 'DecimalNumberChamp', string_value: '42.5')
      expect(extractor.send(:normalize_number, champ)).to eq(42.5)
    end

    it 'retourne nil pour une valeur vide' do
      champ = double('IntegerNumberChamp', __typename: 'IntegerNumberChamp', string_value: '')
      expect(extractor.send(:normalize_number, champ)).to be_nil
    end

    it 'retourne nil pour une valeur invalide' do
      champ = double('IntegerNumberChamp', __typename: 'IntegerNumberChamp', string_value: 'abc')
      expect(extractor.send(:normalize_number, champ)).to be_nil
    end
  end

  describe '#extract_main_table' do
    let(:field_metadata) do
      {
        'Plan de masse' => { 'type' => 'file', 'id' => 10 },
        'Notes' => { 'type' => 'long_text', 'id' => 11 }
      }
    end

    let(:champ_plan) do
      double('PieceJustificativeChamp',
             label: 'Plan de masse',
             __typename: 'PieceJustificativeChamp',
             files: [double('File', filename: 'plan_user.pdf', url: 'https://md/plan_user.pdf', byte_size: 100)])
    end

    let(:annotation_plan_historique) do
      double('PieceJustificativeChamp',
             label: 'Plan de masse',
             __typename: 'PieceJustificativeChamp',
             files: [double('File', filename: 'plan_v1.pdf', url: 'https://md/plan_v1.pdf', byte_size: 50)])
    end

    let(:annotation_notes) do
      double('TextareaChamp',
             label: 'Notes',
             __typename: 'TextareaChamp',
             value: 'note interne')
    end

    let(:dossier) do
      double('Dossier',
             number: 42,
             state: 'en_instruction',
             date_depot: nil,
             date_passage_en_instruction: nil,
             date_traitement: nil,
             usager: nil,
             demandeur: nil,
             champs: [champ_plan],
             annotations: [annotation_plan_historique, annotation_notes])
    end

    it 'ignore les annotations homonymes d\'un champ et conserve la valeur du champ' do
      allow(Rails.logger).to receive(:warn)

      result = extractor.send(:extract_main_table, dossier)

      expect(result['Plan de masse']).to contain_exactly(
        { url: 'https://md/plan_user.pdf', visible_name: 'plan_user.pdf' }
      )
      expect(result['Notes']).to eq('note interne')
      expect(Rails.logger).to have_received(:warn).with(/Plan de masse/)
    end
  end
end
# rubocop:enable Metrics/BlockLength
