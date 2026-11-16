# frozen_string_literal: true

require_relative 'mes_demarches/avis_fetcher'
require_relative 'mes_demarches_to_baserow/sync_coordinator'
require_relative 'mes_demarches_to_baserow/data_extractor'
require_relative 'mes_demarches_to_baserow/field_filter'
require_relative 'mes_demarches_to_baserow/row_upserter'
require_relative 'mes_demarches_to_baserow/mapping'
require_relative 'mes_demarches_to_baserow/avis_syncer'
require_relative 'mes_demarches_to_baserow/avis_table_builder'

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
#       supprimer_orphelins: true
#     mapping:                         # Optionnel - table socle (voir README)
#       Représentant nom: 140066       # stable_id
#       Service: DIREN                 # gabarit / constante
class BaserowSync < FieldChecker
  def version
    super + 1
  end

  def required_fields
    super + %i[baserow]
  end

  def authorized_fields
    super + %i[options mapping]
  end

  def initialize(*args)
    super

    # Validation des paramètres (pattern standard: @errors au lieu de raise)
    # Note: les sous-hash YAML arrivent avec des clés string, pas symbol
    @errors << "Configuration 'baserow.table_id' manquante sur baserow_sync" unless @params[:baserow]&.[]('table_id')

    if @params.dig(:options, 'include_repetable_blocks') == true
      blocks = @params.dig(:options, 'repetable_blocks')
      @errors << "Configuration 'options.repetable_blocks' invalide ou vide sur baserow_sync" if blocks.nil? || !blocks.is_a?(Array) || blocks.empty?
    end

    @errors.concat(MesDemarchesToBaserow::Mapping.erreurs_de_config(@params[:mapping]).map { |erreur| "baserow_sync : #{erreur}" }) if @params.key?(:mapping)

    @coordinator = nil # Créer le coordinator à la demande pour réutiliser les caches
  end

  # Méthode FieldChecker à implémenter
  def process(demarche, dossier)
    super
    return if supprime_par_usager?(demarche, dossier)
    return unless must_check?(dossier)

    Rails.logger.info "BaserowSync: Synchro dossier #{dossier.number} (démarche #{demarche.id})"

    coordinator_for(demarche).sync_dossier(dossier)
  end

  # Hook du moteur : dossier supprimé ou en corbeille. Le filtre etat_du_dossier ne s'applique pas.
  # Les erreurs se propagent : le moteur garde le numéro dans sa file de reprise.
  def deleted(demarche, number)
    coordinator_for(demarche).delete_dossier(number)
  end

  # N'écoute les suppressions que si CE robot a figé la table en DLNUF : une lecture en base,
  # sans appel Baserow. Une table archive (ou de type encore inconnu) ne coûte rien de plus.
  def ecoute_suppressions?(_demarche)
    ReferentielTable.exists?(backend: 'baserow', table_ref: @params[:baserow]&.[]('table_id').to_s, mode: 'dlnuf')
  end

  private

  # Créer ou réutiliser le coordinator selon la démarche
  # Cela permet de bénéficier des caches pour tous les dossiers d'une même démarche
  def coordinator_for(demarche)
    if @coordinator.nil? || @coordinator.demarche_number != demarche.id
      @coordinator = MesDemarchesToBaserow::SyncCoordinator.new(
        demarche.id,
        @params[:baserow],
        @params[:options] || {},
        **options_mapping
      )
    end
    @coordinator
  end

  # Le gabarit s'instancie sur @dossier, posé par FieldChecker#process avant chaque synchronisation.
  def options_mapping
    return {} unless @params[:mapping]

    { mapping: @params[:mapping], gabarit: ->(texte) { instanciate(texte) } }
  end

  # Dossier supprimé par l'usager seul : en DLNUF la ligne est effacée, quel que soit l'état du
  # dossier (testé avant must_check?). En archive, le dossier est synchronisé comme d'habitude.
  # La date est testée en premier : aucun coordinateur n'est construit pour un dossier ordinaire.
  def supprime_par_usager?(demarche, dossier)
    return false if dossier.date_suppression_par_usager.blank?

    coordinator = coordinator_for(demarche)
    return false unless coordinator.mode == :dlnuf

    coordinator.delete_dossier(dossier.number)
    true
  end
end
