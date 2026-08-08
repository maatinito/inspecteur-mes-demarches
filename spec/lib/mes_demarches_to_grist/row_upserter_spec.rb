# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe MesDemarchesToGrist::RowUpserter do
  let(:client) { instance_double(Grist::Client) }
  let(:doc_id) { 'aBC123xYz' }
  let(:table_id) { 'Dossiers' }
  let(:table) { Grist::Table.new(client, doc_id, table_id) }
  let(:options) { {} }
  let(:field_metadata) do
    {
      'Dossier' => { type: 'Integer', id: 'Dossier', isFormula: false },
      'Statut' => { type: 'Choice', id: 'Statut', isFormula: false },
      'Nom' => { type: 'Text', id: 'Nom', isFormula: false },
      'Age' => { type: 'Integer', id: 'Age', isFormula: false }
    }
  end
  let(:upserter) { described_class.new(table, options, field_metadata) }

  describe '#upsert_row' do
    context 'when no existing record is provided' do
      it 'performs upsert and finds the record ID' do
        data = { 'Statut' => 'en_construction', 'Nom' => 'Dupont' }

        expect(client).to receive(:upsert_records).with(
          doc_id, table_id,
          [{ require: { 'Dossier' => 42 }, fields: hash_including('Dossier' => 42) }]
        )

        filter_json = { 'Dossier' => [42] }.to_json
        expect(client).to receive(:list_records).with(
          doc_id, table_id, { filter: filter_json }
        ).and_return({ 'records' => [{ 'id' => 1, 'fields' => { 'Dossier' => 42 } }] })

        result = upserter.upsert_row(42, data)
        expect(result).to eq(1)
      end
    end

    context 'when existing record is provided and no changes' do
      it 'skips upsert' do
        existing_record = {
          'id' => 1,
          'fields' => { 'Dossier' => 42, 'Statut' => 'en_construction', 'Nom' => 'Dupont' }
        }
        data = { 'Statut' => 'en_construction', 'Nom' => 'Dupont' }

        expect(client).not_to receive(:upsert_records)

        result = upserter.upsert_row(42, data, existing_record: existing_record)
        expect(result).to eq(1)
      end
    end

    context 'when existing record is provided and has changes' do
      it 'performs upsert with only changed fields' do
        existing_record = {
          'id' => 1,
          'fields' => { 'Dossier' => 42, 'Statut' => 'en_construction', 'Nom' => 'Dupont' }
        }
        data = { 'Statut' => 'accepte', 'Nom' => 'Dupont' }

        expect(client).to receive(:upsert_records).with(
          doc_id, table_id,
          [{ require: { 'Dossier' => 42 }, fields: hash_including('Statut' => 'accepte') }]
        )

        filter_json = { 'Dossier' => [42] }.to_json
        expect(client).to receive(:list_records).with(
          doc_id, table_id, { filter: filter_json }
        ).and_return({ 'records' => [{ 'id' => 1 }] })

        upserter.upsert_row(42, data, existing_record: existing_record)
      end
    end

    # Écrire la clé métier brute dans une colonne Ref ne produit rien côté Grist
    # (cellule vide, sans erreur) : il faut la forme de recherche ["l", valeur].
    context 'quand la colonne clé est une référence' do
      let(:field_metadata) do
        {
          'Dossier' => { type: 'Ref:Dossiers', id: 'Dossier', isFormula: false },
          'Nom' => { type: 'Text', id: 'Nom', isFormula: false }
        }
      end

      it 'envoie la clé en encodage de recherche, dans require comme dans fields' do
        expect(client).to receive(:upsert_records).with(
          doc_id, table_id,
          [{ require: { 'Dossier' => ['l', 42] }, fields: hash_including('Dossier' => ['l', 42]) }]
        )
        allow(client).to receive(:list_records).and_return({ 'records' => [{ 'id' => 7 }] })

        upserter.upsert_row(42, { 'Nom' => 'Dupont' })
      end

      it 'retrouve la ligne en filtrant sur la clé encodée' do
        allow(client).to receive(:upsert_records)
        filter_json = { 'Dossier' => [['l', 42]] }.to_json
        expect(client).to receive(:list_records).with(
          doc_id, table_id, { filter: filter_json }
        ).and_return({ 'records' => [{ 'id' => 7 }] })

        expect(upserter.upsert_row(42, { 'Nom' => 'Dupont' })).to eq(7)
      end
    end
  end

  describe '#filter_changed_fields' do
    it 'detects text changes' do
      existing = { 'fields' => { 'Nom' => 'Dupont' } }
      new_data = { 'Nom' => 'Martin' }

      result = upserter.send(:filter_changed_fields, new_data, existing)
      expect(result).to eq({ 'Nom' => 'Martin' })
    end

    it 'ignores unchanged text fields' do
      existing = { 'fields' => { 'Nom' => 'Dupont' } }
      new_data = { 'Nom' => 'Dupont' }

      result = upserter.send(:filter_changed_fields, new_data, existing)
      expect(result).to be_empty
    end

    it 'detects number changes' do
      existing = { 'fields' => { 'Age' => 25 } }
      new_data = { 'Age' => 30 }

      result = upserter.send(:filter_changed_fields, new_data, existing)
      expect(result).to eq({ 'Age' => 30 })
    end

    it 'ignores unchanged numbers (string vs int)' do
      existing = { 'fields' => { 'Age' => 25 } }
      new_data = { 'Age' => 25 }

      result = upserter.send(:filter_changed_fields, new_data, existing)
      expect(result).to be_empty
    end

    context 'quand un champ MD est vidé, la cellule Grist est réinitialisée' do
      let(:field_metadata) do
        {
          'Statut' => { type: 'Choice', id: 'Statut', isFormula: false },
          'Nom' => { type: 'Text', id: 'Nom', isFormula: false },
          'Age' => { type: 'Integer', id: 'Age', isFormula: false },
          'Actif' => { type: 'Bool', id: 'Actif', isFormula: false },
          'Thèmes' => { type: 'ChoiceList', id: 'Themes', isFormula: false },
          'PJ' => { type: 'Attachments', id: 'PJ', isFormula: false }
        }
      end

      it 'envoie nil pour un Text vidé quand la cellule est renseignée' do
        existing = { 'fields' => { 'Nom' => 'Dupont' } }

        result = upserter.send(:filter_changed_fields, { 'Nom' => nil }, existing)

        expect(result).to have_key('Nom')
        expect(result['Nom']).to be_nil
      end

      it "envoie nil pour un Choice vidé ('' devient nil)" do
        existing = { 'fields' => { 'Statut' => 'en_construction' } }

        result = upserter.send(:filter_changed_fields, { 'Statut' => '' }, existing)

        expect(result).to have_key('Statut')
        expect(result['Statut']).to be_nil
      end

      it 'envoie nil pour un Integer vidé quand la cellule est renseignée' do
        existing = { 'fields' => { 'Age' => 25 } }

        result = upserter.send(:filter_changed_fields, { 'Age' => nil }, existing)

        expect(result).to have_key('Age')
        expect(result['Age']).to be_nil
      end

      it 'envoie false pour un Bool vidé quand la cellule est à true' do
        existing = { 'fields' => { 'Actif' => true } }

        result = upserter.send(:filter_changed_fields, { 'Actif' => nil }, existing)

        expect(result['Actif']).to be(false)
      end

      it "n'envoie rien pour un Bool vidé quand la cellule est déjà false" do
        existing = { 'fields' => { 'Actif' => false } }

        result = upserter.send(:filter_changed_fields, { 'Actif' => nil }, existing)

        expect(result).not_to have_key('Actif')
      end

      it 'envoie nil pour une ChoiceList vidée quand la cellule est renseignée' do
        existing = { 'fields' => { 'Thèmes' => %w[L Sport] } }

        result = upserter.send(:filter_changed_fields, { 'Thèmes' => ['L'] }, existing)

        expect(result).to have_key('Thèmes')
        expect(result['Thèmes']).to be_nil
      end

      it "ne considère pas ['L'] différent d'une cellule ChoiceList vide (null)" do
        existing = { 'fields' => { 'Thèmes' => nil } }

        result = upserter.send(:filter_changed_fields, { 'Thèmes' => ['L'] }, existing)

        expect(result).not_to have_key('Thèmes')
      end

      it 'ne touche pas aux Attachments quand la nouvelle valeur est nil' do
        existing = { 'fields' => { 'PJ' => ['L', 12] } }

        result = upserter.send(:filter_changed_fields, { 'PJ' => nil }, existing)

        expect(result).not_to have_key('PJ')
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
