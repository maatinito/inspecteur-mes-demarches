# frozen_string_literal: true

class DetecterDoublon < FieldChecker
  DEFAULT_ETATS_ACTIFS = %w[en_construction en_instruction].freeze
  DEFAULT_ETATS_DOUBLONS = %w[en_construction en_instruction accepte].freeze

  def required_fields
    %i[cle]
  end

  def authorized_fields
    super + %i[etats_doublons purge_after_months quand_doublon quand_unique]
  end

  def initialize(params)
    super
    @when_doublon_defs = Array(@params[:quand_doublon])
    @when_unique_defs = Array(@params[:quand_unique])
    @etats_doublons = Set.new(Array(@params[:etats_doublons]).presence || DEFAULT_ETATS_DOUBLONS)
    @states = Set.new(Array(@params[:etat_du_dossier]).presence || DEFAULT_ETATS_ACTIFS)
  end

  def must_check?(_md_dossier)
    true
  end

  def process(demarche, dossier)
    super
    cle = compute_cle
    state = dossier.state.to_s
    depose_at = parse_depose_at(dossier)
    previous_cle = DossierDoublon.find_by(dossier_number: dossier.number)&.cle

    sync_registry(state, cle, depose_at)
    return unless @states.include?(state)

    duplicates = current_duplicates(state, cle, depose_at)
    fire_actions(duplicates, cle)
    recheck_siblings(depose_at, [cle, previous_cle].compact.uniq)
  end

  private

  def compute_cle
    raw = instanciate(@params[:cle].to_s)
    return nil if raw.blank?

    raw.gsub(/\s+/, '').upcase.presence
  end

  def parse_depose_at(dossier)
    raw = dossier.date_depot
    return nil if raw.blank?
    return raw if raw.is_a?(Time) || raw.is_a?(DateTime) || raw.is_a?(Date)

    DateTime.iso8601(raw)
  end

  def registry_eligible?(state, cle, depose_at)
    @etats_doublons.include?(state) && cle.present? && depose_at.present?
  end

  def sync_registry(state, cle, depose_at)
    if registry_eligible?(state, cle, depose_at)
      now = Time.zone.now
      DossierDoublon.upsert(
        {
          demarche_id: @demarche.id,
          dossier_number: @dossier.number,
          cle:,
          state:,
          depose_at:,
          updated_at: now,
          created_at: now
        },
        unique_by: :dossier_number
      )
    else
      DossierDoublon.where(dossier_number: @dossier.number).delete_all
    end
  end

  def current_duplicates(state, cle, depose_at)
    return DossierDoublon.none unless registry_eligible?(state, cle, depose_at)

    DossierDoublon.duplicates_of(
      demarche_id: @demarche.id,
      cle:,
      depose_at:,
      etats: @etats_doublons.to_a,
      purge_after_months: @params[:purge_after_months]
    )
  end

  def fire_actions(duplicates, cle)
    definitions = duplicates.any? ? @when_doublon_defs : @when_unique_defs
    return if definitions.blank?

    context = build_context(duplicates, cle)
    resolved = deep_resolve(definitions, context)
    tasks = InspectorTask.create_tasks(resolved)
    tasks.each do |task|
      Rails.logger.tagged(task.name) do
        task.demarche = @demarche
        task.process(@demarche, @dossier)
        @updated_dossiers += task.updated_dossiers if task.respond_to?(:updated_dossiers)
        @dossiers_to_recheck += task.dossiers_to_recheck if task.respond_to?(:dossiers_to_recheck)
      end
    end
  end

  def build_context(duplicates, cle)
    refs = duplicates.map { |d| "##{d.dossier_number}" }
    {
      doublons_refs: refs.join(', '),
      doublons_count: duplicates.size.to_s,
      cle: cle.to_s
    }
  end

  def deep_resolve(value, context)
    case value
    when Hash then value.transform_values { |v| deep_resolve(v, context) }
    when Array then value.map { |v| deep_resolve(v, context) }
    when String then instanciate(value, context)
    else value
    end
  end

  # Asymétrique : ne réveille que les dossiers déposés APRÈS celui-ci.
  # Les antérieurs sont par construction non impactés (leur statut "légitime"
  # ne dépend que de leurs propres antérieurs).
  def recheck_siblings(depose_at, cles)
    DossierDoublon.posterior_siblings(demarche_id: @demarche.id, cles:, depose_at:)
                  .each { |number| recheck(number) }
  end
end
