# frozen_string_literal: true

require_relative 'baserow_sync/sync_coordinator'
require_relative 'baserow_sync/data_extractor'
require_relative 'baserow_sync/field_filter'
require_relative 'baserow_sync/row_upserter'

# Synchronisation des dossiers Mes-Démarches vers Baserow
#
# Cette classe est un InspectorTask qui synchronise automatiquement les dossiers
# vers des tables Baserow configurées. Elle est intégrée dans le système
# VerificationService et s'exécute pour chaque dossier traité.
#
# Configuration YAML exemple:
#   baserow_sync:
#     baserow:
#       table_id: 42
#       token_config: 'tftn'
#       application_id: 123
#       workspace_id: 456
#     options:
#       sync_mode: 'incremental'
#       include_repetable_blocks: true
#       repetable_blocks:
#         - champ_id: "Q2hhbXAtOTAw..."
#           table_name: "Bénéficiaires"
class BaserowSync < InspectorTask
  # Méthodes InspectorTask à implémenter
  def process(demarche, dossier)
    Rails.logger.info "BaserowSync: Synchro dossier #{dossier.number} (démarche #{demarche.number})"

    coordinator = BaserowSync::SyncCoordinator.new(
      demarche.number,
      @params[:baserow],
      @params[:options] || {}
    )

    coordinator.sync_dossier(dossier)
  rescue StandardError => e
    Rails.logger.error "BaserowSync: Erreur synchro dossier #{dossier.number}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    Sentry.capture_exception(e, extra: { dossier: dossier.number, demarche: demarche.number })

    # Continuer ou lever l'erreur selon la config
    raise unless @params.dig(:options, :continue_on_error) == true
  end

  # Pas de filtre d'état - on synchronise tous les dossiers traités
  def must_process?(_dossier)
    true
  end

  # Champs autorisés dans la configuration
  def authorized_fields
    %i[baserow options]
  end

  private

  def validate_params!
    raise ArgumentError, "Configuration 'baserow.table_id' manquante" unless @params[:baserow]&.[](:table_id)

    return unless @params.dig(:options, :include_repetable_blocks) == true

    blocks = @params.dig(:options, :repetable_blocks)
    return unless blocks.nil? || !blocks.is_a?(Array) || blocks.empty?

    raise ArgumentError, "Configuration 'options.repetable_blocks' invalide ou vide"
  end
end
