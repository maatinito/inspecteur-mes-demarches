# frozen_string_literal: true

# Helpers d'implémentation isolés dans un module pour faciliter les tests et
# éviter de polluer la closure du `namespace :schema_targets`.
module SchemaTargetsBackfill
  # Conventions de nommage utilisées par le nouveau dashboard
  # (cf. Admin::SchemaBuilderController#main_table_name_for et
  # SchemaBuilders::AvisBuilder::TABLE_NAME).
  MAIN_TABLE_NAME_FORMAT = 'Dossiers démarche %<id>s'
  AVIS_TABLE_NAME = 'Avis'

  module_function

  def detect_target(demarche, target_type)
    adapter = adapter_for(target_type)
    expected_main_table_name = format(MAIN_TABLE_NAME_FORMAT, id: demarche.id)

    adapter.list_workspaces.each do |workspace|
      workspace_id = workspace['id'] || workspace[:id]
      Array(adapter.list_applications(workspace_id)).each do |application|
        application_id = application['id'] || application[:id]
        tables = Array(adapter.list_tables(application_id))

        main_table = tables.find { |t| (t['name'] || t[:name] || t['id'] || t[:id])&.to_s == expected_main_table_name }
        next unless main_table

        avis_table = tables.find { |t| (t['name'] || t[:name] || t['id'] || t[:id])&.to_s == AVIS_TABLE_NAME }

        return {
          workspace_id: workspace_id,
          application_id: application_id,
          main_table_id: main_table['id'] || main_table[:id],
          avis_table_id: avis_table ? (avis_table['id'] || avis_table[:id]) : nil
        }
      end
    end

    nil
  rescue StandardError => e
    Rails.logger.warn "Backfill detection failed for #{demarche.id} #{target_type}: #{e.message}"
    nil
  end

  def adapter_for(target_type)
    case target_type
    when :baserow then SchemaBuilders::BaserowTarget.new
    when :grist   then SchemaBuilders::GristTarget.new
    else raise ArgumentError, "target_type inconnu: #{target_type.inspect}"
    end
  end
end

namespace :schema_targets do
  desc 'Backfill SchemaTarget records for démarches already synchronized to Baserow/Grist'
  task backfill: :environment do
    backfilled = { baserow: 0, grist: 0, skipped: 0 }

    Demarche.find_each do |demarche|
      %i[baserow grist].each do |target_type|
        if demarche.schema_targets.exists?(target_type: target_type.to_s)
          backfilled[:skipped] += 1
          next
        end

        result = SchemaTargetsBackfill.detect_target(demarche, target_type)
        next unless result

        demarche.schema_targets.create!(
          target_type: target_type.to_s,
          workspace_external_id: result[:workspace_id].to_s,
          application_external_id: result[:application_id].to_s,
          main_table_external_id: result[:main_table_id].to_s,
          avis_table_external_id: result[:avis_table_id]&.to_s
        )
        backfilled[target_type] += 1
        puts "[#{target_type}] backfilled démarche #{demarche.id}"
      end
    end

    puts "\nDone: backfilled #{backfilled[:baserow]} Baserow + #{backfilled[:grist]} Grist (skipped #{backfilled[:skipped]} existing)."
  end
end
