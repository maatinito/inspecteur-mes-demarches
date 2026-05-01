# frozen_string_literal: true

class DeadLineChecker < FieldChecker
  def authorized_fields
    super + %i[recevabilite instruction annotation_alertes]
  end

  def initialize(params)
    super
    @phases = {}
    parse_phase(:recevabilite)
    parse_phase(:instruction)
    @errors << 'Au moins une phase (recevabilite ou instruction) doit être configurée' if @phases.empty?

    states = []
    states << 'en_construction' if @phases[:recevabilite]
    states << 'en_instruction' if @phases[:instruction]
    @states = Set.new(states)
  end

  def process(demarche, dossier)
    super
    clear_schedule(dossier)
    return unless must_check?(dossier)

    phase_key = dossier.state == 'en_construction' ? :recevabilite : :instruction
    config = @phases[phase_key]
    return unless config

    duree_effective = compute_elapsed_days(phase_key, dossier)
    jours_restants = config[:duree_max] - duree_effective

    variables = {
      jours_restants: jours_restants,
      duree_effective: duree_effective,
      duree_max: config[:duree_max],
      phase: phase_key.to_s
    }

    update_annotation(config[:annotation_jours_restants], jours_restants)
    check_thresholds(config[:seuils], jours_restants, variables)
    schedule_next_check(dossier, config[:seuils], jours_restants)
  end

  def self.corrections_query
    @corrections_query ||= MesDemarches::Client.parse <<-GRAPHQL
      query DossierCorrections($dossier: Int!) {
        dossier(number: $dossier) {
          messages {
            createdAt
            correction {
              dateResolution
            }
          }
        }
      }
    GRAPHQL
  end

  private

  def parse_phase(key)
    config = @params[key]
    return if config.blank?

    config = config.symbolize_keys
    @phases[key] = {
      duree_max: config[:duree_max].to_i,
      annotation_jours_restants: config[:annotation_jours_restants],
      seuils: parse_seuils(config[:seuils])
    }
  end

  def parse_seuils(seuils)
    return [] if seuils.blank?

    parsed = seuils.map do |seuil|
      seuil = seuil.symbolize_keys
      {
        jours: seuil[:jours].to_i,
        alerter: parse_destinataires(seuil[:alerter]),
        objet: seuil[:objet],
        message: seuil[:message],
        label: seuil[:label]
      }
    end
    parsed.sort_by { |s| -s[:jours] }
  end

  def parse_destinataires(destinataires)
    return [] if destinataires.blank?

    destinataires.is_a?(String) ? destinataires.split(/\s*,\s*/) : Array(destinataires)
  end

  def update_annotation(annotation_name, jours_restants)
    return if annotation_name.blank?

    changed = SetAnnotationValue.set_value(@dossier, instructeur_id, annotation_name, jours_restants.to_i)
    dossier_updated(@dossier) if changed
  end

  def check_thresholds(seuils, jours_restants, variables)
    return if seuils.blank?

    triggered = load_triggered_thresholds
    newly_triggered = []

    seuils.each do |seuil|
      threshold = seuil[:jours]
      next if triggered.include?(threshold)
      next unless jours_restants <= threshold

      send_alert(seuil, variables)
      apply_label(seuil[:label])
      newly_triggered << threshold
    end

    save_triggered_thresholds(triggered + newly_triggered) if newly_triggered.present?
  end

  def load_triggered_thresholds
    return [] if @params[:annotation_alertes].blank?

    value = annotation(@params[:annotation_alertes], warn_if_empty: false)&.value
    return [] if value.blank?

    value.split(',').map { |s| s.strip.to_i }
  end

  def save_triggered_thresholds(thresholds)
    return if @params[:annotation_alertes].blank?

    SetAnnotationValue.set_value(
      @dossier,
      instructeur_id,
      @params[:annotation_alertes],
      thresholds.sort.reverse.join(', ')
    )
    dossier_updated(@dossier)
  end

  def send_alert(seuil, variables)
    return if seuil[:alerter].blank?

    subject = instanciate(seuil[:objet], variables)
    body = instanciate(seuil[:message], variables)
    recipients = seuil[:alerter].join(',')

    NotificationMailer.with({ subject:, message: body, recipients: }).user_mail.deliver_later
  end

  def apply_label(label_name)
    return if label_name.blank?

    label_id = DossierLabel.find_label_id(@demarche.id, label_name)
    if label_id
      DossierLabel.add(@dossier.id, label_id)
    else
      Rails.logger.warn("Label '#{label_name}' introuvable sur la démarche #{@demarche.id}")
    end
  end

  # --- Scheduling ---

  def task_identifier
    "dead_line_checker/#{@dossier.number}"
  end

  def clear_schedule(dossier)
    ScheduledTask.clear(dossier: dossier.number, task: task_identifier)
  end

  def schedule_next_check(dossier, seuils, jours_restants)
    return if seuils.blank?

    triggered = load_triggered_thresholds
    next_seuil = seuils.select { |s| !triggered.include?(s[:jours]) && jours_restants > s[:jours] }
                       .max_by { |s| s[:jours] }
    return unless next_seuil

    days_until_seuil = jours_restants - next_seuil[:jours]
    run_at = days_until_seuil.days.from_now.beginning_of_day + 7.hours
    ScheduledTask.enqueue(dossier.number, task_identifier, @params, run_at)
  end

  # --- Duration calculations ---

  def compute_elapsed_days(phase, dossier)
    case phase
    when :instruction
      compute_instruction_days(dossier)
    when :recevabilite
      compute_recevabilite_days(dossier)
    else
      0
    end
  end

  def compute_instruction_days(dossier)
    intervals = build_state_intervals(dossier.traitements, 'en_instruction')
    intervals_to_days(intervals)
  end

  def compute_recevabilite_days(dossier)
    construction_intervals = build_state_intervals(
      dossier.traitements, 'en_construction', dossier.date_depot
    )
    correction_intervals = build_correction_intervals(fetch_dossier_messages(dossier))

    total = construction_intervals.sum do |ci|
      duration = ci[:end] - ci[:start]
      correction_intervals.each do |corr|
        overlap_start = [ci[:start], corr[:start]].max
        overlap_end = [ci[:end], corr[:end]].min
        duration -= (overlap_end - overlap_start) if overlap_end > overlap_start
      end
      [duration, 0].max
    end

    (total / 1.day.to_f).floor
  end

  def fetch_dossier_messages(dossier)
    result = MesDemarches.query(self.class.corrections_query::DossierCorrections, variables: { dossier: dossier.number })
    result.data&.dossier&.messages || []
  end

  def build_state_intervals(traitements, target_state, initial_date = nil)
    sorted = traitements.sort_by(&:processed_at)
    intervals = []

    if initial_date.present?
      first_transition = sorted.first
      if first_transition.nil?
        intervals << { start: parse_time(initial_date), end: Time.zone.now }
      elsif first_transition.state != target_state
        intervals << { start: parse_time(initial_date), end: parse_time(first_transition.processed_at) }
      end
    end

    entry_time = nil
    sorted.each do |t|
      if t.state == target_state
        entry_time ||= parse_time(t.processed_at)
      elsif entry_time
        intervals << { start: entry_time, end: parse_time(t.processed_at) }
        entry_time = nil
      end
    end

    intervals << { start: entry_time, end: Time.zone.now } if entry_time
    intervals
  end

  def build_correction_intervals(messages)
    return [] if messages.blank?

    messages.select { |m| m.respond_to?(:correction) && m.correction.present? }.map do |m|
      {
        start: parse_time(m.created_at),
        end: m.correction.date_resolution.present? ? parse_time(m.correction.date_resolution) : Time.zone.now
      }
    end
  end

  def intervals_to_days(intervals)
    total = intervals.sum { |i| i[:end] - i[:start] }
    (total / 1.day.to_f).floor
  end

  def parse_time(value)
    case value
    when Time, DateTime
      value.in_time_zone
    when String
      Time.zone.parse(value)
    else
      value
    end
  end
end
