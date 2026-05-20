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
    previous_cle = DossierDoublon.find_by(dossier_number: dossier.number)&.cle

    sync_registry(state, cle)
    return unless @states.include?(state)

    duplicates = current_duplicates(state, cle, dossier)
    fire_actions(duplicates, cle)
    recheck_siblings(dossier, [cle, previous_cle].compact.uniq)
  end

  private

  def compute_cle
    raw = instanciate(@params[:cle].to_s)
    return nil if raw.blank?

    raw.gsub(/\s+/, '').upcase.presence
  end

  def registry_eligible?(state, cle)
    @etats_doublons.include?(state) && cle.present?
  end

  def sync_registry(state, cle)
    if registry_eligible?(state, cle)
      now = Time.zone.now
      DossierDoublon.upsert(
        {
          demarche_id: @demarche.id,
          dossier_number: @dossier.number,
          cle:,
          state:,
          date_passage_en_construction: @dossier.date_passage_en_construction,
          updated_at: now,
          created_at: now
        },
        unique_by: :dossier_number
      )
    else
      DossierDoublon.where(dossier_number: @dossier.number).delete_all
    end
  end

  def current_duplicates(state, cle, dossier)
    return DossierDoublon.none unless registry_eligible?(state, cle)

    DossierDoublon.duplicates_of(
      demarche_id: @demarche.id,
      cle:,
      dossier_number: dossier.number,
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

  def recheck_siblings(dossier, cles)
    return if cles.empty?

    siblings = DossierDoublon.for_demarche(@demarche.id)
                             .where(cle: cles)
                             .where.not(dossier_number: dossier.number)
                             .pluck(:dossier_number)
    siblings.each { |number| recheck(number) }
  end
end
