# frozen_string_literal: true

require_relative 'mes_demarches_to_baserow/sync_coordinator'
require_relative 'mes_demarches_to_baserow/data_extractor'
require_relative 'mes_demarches_to_baserow/field_filter'
require_relative 'mes_demarches_to_baserow/row_upserter'

# Synchronisation des dossiers Mes-Démarches vers Baserow
#
# Cette classe est un FieldChecker qui synchronise automatiquement les dossiers
# vers des tables Baserow configurées. Elle est intégrée dans le système
# VerificationService et s'exécute pour chaque dossier traité.
#
# Configuration YAML exemple:
#   baserow_sync:
#     etat_du_dossier: en_instruction  # Optionnel - filtre par état
#     baserow:
#       table_id: 42
#       token_config: 'tftn'
#     options:
#       continuer_si_erreur: true
#       supprimer_orphelins: true
class BaserowSync < FieldChecker
  def version
    super + 1
  end

  def required_fields
    super + %i[baserow]
  end

  def authorized_fields
    super + %i[options]
  end

  def initialize(*args)
    super

    # Validation des paramètres (pattern standard: @errors au lieu de raise)
    @errors << "Configuration 'baserow.table_id' manquante sur baserow_sync" unless @params[:baserow]&.[](:table_id)

    if @params.dig(:options, :include_repetable_blocks) == true
      blocks = @params.dig(:options, :repetable_blocks)
      @errors << "Configuration 'options.repetable_blocks' invalide ou vide sur baserow_sync" if blocks.nil? || !blocks.is_a?(Array) || blocks.empty?
    end

    @coordinator = nil # Créer le coordinator à la demande pour réutiliser les caches
  end

  # Méthode FieldChecker à implémenter
  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    Rails.logger.info "BaserowSync: Synchro dossier #{dossier.number} (démarche #{demarche.id})"

    # Créer ou réutiliser le coordinator selon la démarche
    # Cela permet de bénéficier des caches pour tous les dossiers d'une même démarche
    if @coordinator.nil? || @coordinator.demarche_number != demarche.id
      @coordinator = MesDemarchesToBaserow::SyncCoordinator.new(
        demarche.id,
        @params[:baserow],
        @params[:options] || {}
      )
    end

    @coordinator.sync_dossier(dossier)
  rescue StandardError => e
    Rails.logger.error "BaserowSync: Erreur synchro dossier #{dossier.number}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    Sentry.capture_exception(e, extra: { dossier: dossier.number, demarche: demarche.id })

    # Continuer ou lever l'erreur selon la config
    raise unless @params.dig(:options, :continuer_si_erreur) == true
  end
end
