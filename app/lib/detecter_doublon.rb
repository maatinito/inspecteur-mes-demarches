# frozen_string_literal: true

class DetecterDoublon < FieldChecker
  DEFAULT_ETATS_ACTIFS = %w[en_construction en_instruction].freeze
  DEFAULT_ETATS_DOUBLONS = %w[en_construction en_instruction accepte].freeze

  def required_fields
    %i[cle]
  end

  def authorized_fields
    super + %i[etats_doublons purge_after_months quand_doublon quand_unique message]
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

  # Bloque l'usage dans `when_ok:` — la propagation de @dossiers_to_recheck
  # n'est active qu'en phase `controles:` (cf. moteur VerificationService).
  # Mettre `detecter_doublon` dans `when_ok:` ferait silencieusement perdre
  # le réveil des frères postérieurs.
  def process(_demarche, _dossier)
    raise NotImplementedError,
          'detecter_doublon doit être placé dans `controles:`, pas `when_ok:` ' \
          '(le recheck des frères ne se propage qu\'en phase de contrôle).'
  end

  def check(dossier)
    @dossier = dossier

    cle = compute_cle
    state = dossier.state.to_s
    depose_at = parse_depose_at(dossier)
    previous_cle = DossierDoublon.find_by(dossier_number: dossier.number)&.cle

    sync_registry(state, cle, depose_at)
    return unless @states.include?(state)

    duplicates = current_duplicates(state, cle, depose_at)
    context = build_context(duplicates, cle)
    fire_actions(duplicates, context)
    fire_message(duplicates, cle, context)
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
        unique_by: :dossier_number,
        update_only: %i[cle state depose_at]
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

  def fire_actions(duplicates, context)
    definitions = duplicates.any? ? @when_doublon_defs : @when_unique_defs
    return if definitions.blank?

    resolved = deep_resolve(definitions, context)
    tasks = InspectorTask.create_tasks(resolved)
    tasks.each do |task|
      Rails.logger.tagged(task.name) do
        task.demarche = @demarche
        task.process(@demarche, @dossier)
        # Workaround : ne pas propager `task.updated_dossiers`. Le contrat actuel
        # (`field_checker.rb:256` stocke Integer ; `verification_service.rb:297`
        # attend un objet) provoque NoMethodError sur `dossier.number`. À retirer
        # quand la refonte `@dossier_updated boolean` (PR dédiée) sera mergée.
        @dossiers_to_recheck += task.dossiers_to_recheck if task.respond_to?(:dossiers_to_recheck)
      end
    end
  end

  def fire_message(duplicates, cle, context)
    return if duplicates.empty? || @params[:message].blank?

    add_message(message_anchor, cle, instanciate(@params[:message], context))
  end

  # Point d'accroche affiché à l'usager : extrait les noms de champs de la template
  # `@params[:cle]` (ex. "{ChampX} {ChampY}" → "ChampX, ChampY"). Fallback sur la
  # valeur brute si la clé est un littéral sans variables.
  def message_anchor
    @message_anchor ||= begin
      tpl = @params[:cle].to_s
      names = tpl.scan(/\{([^}]+)\}/).flatten
      names.any? ? names.join(', ') : tpl
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
