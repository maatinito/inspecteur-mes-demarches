# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchemaBuilderHelper do
  describe '#main_table_status_label' do
    it 'retourne "Jamais sync" sans last_synced_at' do
      target = build(:schema_target, last_synced_at: nil, main_table_external_id: nil)
      expect(helper.main_table_status_label(target)).to eq('Jamais sync')
    end

    it 'retourne la date formatée si sync' do
      target = build(:schema_target, last_synced_at: Time.zone.parse('2026-05-15 10:00'), main_table_external_id: '99')
      expect(helper.main_table_status_label(target)).to include('Sync OK')
    end
  end

  describe '#avis_status_label' do
    it 'retourne "Jamais sync" sans last_synced_at' do
      target = build(:schema_target, last_synced_at: nil, avis_table_external_id: nil)
      expect(helper.avis_status_label(target)).to eq('Jamais sync')
    end

    it 'retourne "Jamais sync" si avis_table_external_id absent même avec last_synced_at' do
      target = build(:schema_target, last_synced_at: Time.zone.now, avis_table_external_id: nil)
      expect(helper.avis_status_label(target)).to eq('Jamais sync')
    end

    it 'retourne la date formatée si sync' do
      target = build(:schema_target, last_synced_at: Time.zone.parse('2026-05-15 10:00'), avis_table_external_id: 'a99')
      expect(helper.avis_status_label(target)).to include('Sync OK')
    end
  end
end
