# frozen_string_literal: true

module SchemaBuilderHelper
  def main_table_status_label(target)
    if target.last_synced_at.present? && target.main_table_external_id.present?
      "Sync OK le #{l target.last_synced_at, format: :short}"
    else
      'Jamais sync'
    end
  end

  def avis_status_label(target)
    if target.last_synced_at.present? && target.avis_table_external_id.present?
      "Sync OK le #{l target.last_synced_at, format: :short}"
    else
      'Jamais sync'
    end
  end

  def block_status_label(block)
    if block.last_synced_at.present? && block.backend_table_id.present?
      'Sync OK'
    elsif block.backend_table_id.blank?
      'Jamais sync'
    else
      'Erreur'
    end
  end

  # Construit l'URL PATCH d'exclusion pour un champ (table principale ou bloc).
  # Utilisé par le Stimulus controller `exclusion-toggle`.
  def toggle_url_for(target, scope, field, block_id: nil)
    case scope
    when :main_table
      toggle_main_table_field_exclusion_admin_demarche_schema_path(
        demarche_demarche_id: target.demarche_id,
        target: target.target_type,
        field_id: field[:id]
      )
    when :block_field
      toggle_block_field_exclusion_admin_demarche_schema_path(
        demarche_demarche_id: target.demarche_id,
        target: target.target_type,
        block_id: block_id,
        field_id: field[:id]
      )
    end
  end
end
