# frozen_string_literal: true

require_relative 'mes_demarches_to_grist/sync_coordinator'
require_relative 'mes_demarches_to_grist/data_extractor'
require_relative 'mes_demarches_to_grist/field_filter'
require_relative 'mes_demarches_to_grist/row_upserter'

# Synchronisation des dossiers Mes-Démarches vers Grist
#
# Cette classe est un FieldChecker qui synchronise automatiquement les dossiers
# vers des tables Grist configurées. Elle est intégrée dans le système
# VerificationService et s'exécute pour chaque dossier traité.
#
# Configuration YAML exemple:
#   grist_sync:
#     etat_du_dossier: [en_construction, en_instruction, accepte, sans_suite, refuse]
#     grist:
#       doc_id: 'aBC123xYz'
#       table_id: 'Dossiers'
#     options:
#       continuer_si_erreur: true
#       supprimer_orphelins: true
class GristSync < FieldChecker
  def version
    super + 1
  end

  def required_fields
    super + %i[grist]
  end

  def authorized_fields
    super + %i[options]
  end

  def initialize(*args)
    super

    # Validation des paramètres
    @errors << "Configuration 'grist.doc_id' manquante sur grist_sync" unless @params[:grist]&.[]('doc_id')
    @errors << "Configuration 'grist.table_id' manquante sur grist_sync" unless @params[:grist]&.[]('table_id')

    if @params.dig(:options, 'include_repetable_blocks') == true
      blocks = @params.dig(:options, 'repetable_blocks')
      @errors << "Configuration 'options.repetable_blocks' invalide ou vide sur grist_sync" if blocks.nil? || !blocks.is_a?(Array) || blocks.empty?
    end

    @coordinator = nil
  end

  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    Rails.logger.info "GristSync: Synchro dossier #{dossier.number} (démarche #{demarche.id})"

    if @coordinator.nil? || @coordinator.demarche_number != demarche.id
      @coordinator = MesDemarchesToGrist::SyncCoordinator.new(
        demarche.id,
        @params[:grist],
        @params[:options] || {}
      )
    end

    @coordinator.sync_dossier(dossier)
  rescue StandardError => e
    Rails.logger.error "GristSync: Erreur synchro dossier #{dossier.number}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    Sentry.capture_exception(e, extra: { dossier: dossier.number, demarche: demarche.id })

    raise unless @params.dig(:options, 'continuer_si_erreur') == true
  end
end
