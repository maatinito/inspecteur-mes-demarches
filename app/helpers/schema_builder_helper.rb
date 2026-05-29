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
end
