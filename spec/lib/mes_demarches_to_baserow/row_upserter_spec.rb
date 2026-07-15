# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MesDemarchesToBaserow::RowUpserter do
  let(:table) { double('Baserow::Table') }
  let(:field_metadata) do
    {
      'Programme' => { 'type' => 'single_select', 'id' => 1 },
      'Notes' => { 'type' => 'long_text', 'id' => 2 }
    }
  end

  let(:upserter) { described_class.new(table, {}, field_metadata) }

  describe '#filter_changed_fields' do
    context 'quand un single_select reçoit une chaîne vide' do
      it "n'envoie pas '' quand la cellule Baserow est renseignée (vider = chantier séparé)" do
        existing_row = { 'id' => 397, 'Programme' => { 'id' => 5, 'value' => '962 01' } }

        changed = upserter.send(:filter_changed_fields, { 'Programme' => '' }, existing_row)

        expect(changed).not_to have_key('Programme')
      end

      it "n'envoie pas '' quand la cellule Baserow est vide" do
        existing_row = { 'id' => 397, 'Programme' => nil }

        changed = upserter.send(:filter_changed_fields, { 'Programme' => '' }, existing_row)

        expect(changed).not_to have_key('Programme')
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
end
