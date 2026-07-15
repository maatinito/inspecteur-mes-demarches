# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MesDemarchesToBaserow::RowUpserter do
  let(:table) { double('Baserow::Table') }
  let(:field_metadata) do
    {
      'Programme' => { 'type' => 'single_select', 'id' => 1 },
      'Notes' => { 'type' => 'long_text', 'id' => 2 },
      'Thèmes' => { 'type' => 'multiple_select', 'id' => 3 },
      'Association' => { 'type' => 'link_row', 'id' => 4 },
      'Accepte conditions' => { 'type' => 'boolean', 'id' => 5 },
      'Date de dépôt' => { 'type' => 'date', 'id' => 6 }
    }
  end

  let(:upserter) { described_class.new(table, {}, field_metadata) }

  describe '#filter_changed_fields' do
    context 'quand un champ MD est vidé (nil ou blank), la cellule Baserow est réinitialisée' do
      it 'envoie nil pour un single_select vidé quand la cellule est renseignée' do
        existing_row = { 'id' => 397, 'Programme' => { 'id' => 5, 'value' => '962 01' } }

        changed = upserter.send(:filter_changed_fields, { 'Programme' => '' }, existing_row)

        expect(changed).to have_key('Programme')
        expect(changed['Programme']).to be_nil
      end

      it "n'envoie rien pour un single_select vidé quand la cellule est déjà vide" do
        existing_row = { 'id' => 397, 'Programme' => nil }

        changed = upserter.send(:filter_changed_fields, { 'Programme' => '' }, existing_row)

        expect(changed).not_to have_key('Programme')
      end

      it 'envoie nil pour un texte vidé quand la cellule est renseignée' do
        existing_row = { 'id' => 397, 'Notes' => 'ancienne note' }

        changed = upserter.send(:filter_changed_fields, { 'Notes' => nil }, existing_row)

        expect(changed).to have_key('Notes')
        expect(changed['Notes']).to be_nil
      end

      it 'envoie [] pour un multiple_select vidé quand la cellule est renseignée' do
        existing_row = { 'id' => 397, 'Thèmes' => [{ 'id' => 1, 'value' => 'Sport' }] }

        changed = upserter.send(:filter_changed_fields, { 'Thèmes' => nil }, existing_row)

        expect(changed['Thèmes']).to eq([])
      end

      it 'envoie [] pour un link_row vidé quand la cellule est renseignée' do
        existing_row = { 'id' => 397, 'Association' => [{ 'id' => 12, 'value' => 'AS Tefana' }] }

        changed = upserter.send(:filter_changed_fields, { 'Association' => nil }, existing_row)

        expect(changed['Association']).to eq([])
      end

      it 'envoie false pour un boolean vidé quand la cellule est à true' do
        existing_row = { 'id' => 397, 'Accepte conditions' => true }

        changed = upserter.send(:filter_changed_fields, { 'Accepte conditions' => nil }, existing_row)

        expect(changed['Accepte conditions']).to be(false)
      end

      it "n'envoie rien pour un boolean vidé quand la cellule est déjà false" do
        existing_row = { 'id' => 397, 'Accepte conditions' => false }

        changed = upserter.send(:filter_changed_fields, { 'Accepte conditions' => nil }, existing_row)

        expect(changed).not_to have_key('Accepte conditions')
      end

      it 'envoie nil pour une date vidée quand la cellule est renseignée' do
        existing_row = { 'id' => 397, 'Date de dépôt' => '2026-01-15' }

        changed = upserter.send(:filter_changed_fields, { 'Date de dépôt' => nil }, existing_row)

        expect(changed).to have_key('Date de dépôt')
        expect(changed['Date de dépôt']).to be_nil
      end
    end

    context 'quand un single_select reçoit une valeur renseignée' do
      it 'envoie la valeur quand elle diffère de la cellule existante' do
        existing_row = { 'id' => 397, 'Programme' => { 'id' => 5, 'value' => '962 01' } }

        changed = upserter.send(:filter_changed_fields, { 'Programme' => '963 02' }, existing_row)

        expect(changed['Programme']).to eq('963 02')
      end

      it "n'envoie rien quand la valeur est identique" do
        existing_row = { 'id' => 397, 'Programme' => { 'id' => 5, 'value' => '962 01' } }

        changed = upserter.send(:filter_changed_fields, { 'Programme' => '962 01' }, existing_row)

        expect(changed).not_to have_key('Programme')
      end
    end
  end

  describe '#upsert_row (création)' do
    it 'écarte les valeurs nil à la création (rien à réinitialiser)' do
      created = nil
      allow(table).to receive(:create_row) { |data|
        created = data
        { 'id' => 42 }
      }

      upserter.upsert_row(613_255, { 'Programme' => nil, 'Notes' => 'note' }, existing_row: nil)

      expect(created).to eq('Notes' => 'note', 'Dossier' => 613_255)
    end
  end
end
