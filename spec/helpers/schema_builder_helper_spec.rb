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

  describe '#block_status_label' do
    it 'retourne "Jamais sync" sans backend_table_id' do
      block = build(:schema_block_target, last_synced_at: nil, backend_table_id: nil)
      expect(helper.block_status_label(block)).to eq('Jamais sync')
    end

    it 'retourne "Sync OK" si last_synced_at et backend_table_id sont présents' do
      block = build(:schema_block_target, last_synced_at: Time.zone.now, backend_table_id: 'bt1')
      expect(helper.block_status_label(block)).to eq('Sync OK')
    end

    it 'retourne "Erreur" si backend_table_id présent mais last_synced_at absent' do
      block = build(:schema_block_target, last_synced_at: nil, backend_table_id: 'bt1')
      expect(helper.block_status_label(block)).to eq('Erreur')
    end
  end

  describe '#toggle_url_for' do
    let(:demarche) { create(:demarche) }
    let(:target) { create(:schema_target, demarche: demarche, target_type: 'baserow') }
    let(:field) { { id: 'champ_xyz', label: 'Nom', type: 'text' } }

    it 'génère l\'URL d\'exclusion pour la table principale' do
      url = helper.toggle_url_for(target, :main_table, field)
      expect(url).to include("/admin/demarches/#{demarche.id}/schema/targets/baserow/main_table/fields/champ_xyz/exclusion")
    end

    it 'génère l\'URL d\'exclusion pour un champ de bloc' do
      url = helper.toggle_url_for(target, :block_field, field, block_id: 'b1')
      expect(url).to include("/admin/demarches/#{demarche.id}/schema/targets/baserow/blocks/b1/fields/champ_xyz/exclusion")
    end

    it 'retourne nil pour un scope inconnu' do
      expect(helper.toggle_url_for(target, :unknown, field)).to be_nil
    end
  end
end
