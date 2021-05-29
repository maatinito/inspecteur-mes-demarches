# frozen_string_literal: true

class VerificationService
  attr_reader :messages

  @@config = nil

  def check
    VerificationService.config.filter { |_k, d| d.key? 'demarches' }.each do |procedure_name, procedure|
      @pieces_messages = get_pieces_messages(procedure_name, procedure)
      @instructeur_email = instructeur_email(procedure)
      @send_messages = procedure['messages_automatiques']
      @inform_annotation = procedure['annotation_information']
      procedure['name'] = procedure_name
      controls = create_controls(procedure)
      @procedure = procedure
      check_updated_dossiers(controls)
      check_failed_dossiers(controls)
      check_updated_controls(controls)
    rescue StandardError => e
      Rails.logger.error(e.message)
      e.backtrace.each { |b| Rails.logger.debug(b) }
    end
  end

  def post_message(dossier_number)
    graphql = MesDemarches::Client.query(MesDemarches::Queries::DossierId,
                                         variables: { number: dossier_number })
    if graphql.data.dossier?
      md_dossier = graphql.data.dossier
      checks = Check.where(dossier: dossier_number).all
      if checks.present? && md_dossier.present?
        demarche = checks.first.demarche_id
        VerificationService.config.filter { |_k, d| (d.key? 'demarches') && d['demarches'].include?(demarche) }.each do |procedure_name, procedure|
          @pieces_messages = get_pieces_messages(procedure_name, procedure)
        end
        inform(md_dossier, checks)
      end
    end
  end

  def self.config
    file_mtime = File.mtime(config_file_name)
    if @@config.nil? || @@config_time < file_mtime
      @@config = YAML.safe_load(File.read(config_file_name), [], [], true)
      @@config_time = file_mtime
    end
    @@config
  end

  def self.config_file_name
    @@config_file_name ||= Rails.root.join('storage', 'auto_instructeur.yml')
  end

  private

  EPOCH = Time.zone.parse('2000-01-01 00:00')

  def instructeur_email(procedure)
    result = procedure['email_instructeur']
    raise ArgumentError, "#{procedure_name} devrait définir 'email_instructeur' pour définir qui poste les messages aux usagers" if result.empty?

    result
  end

  def on_dossier(dossier_number)
    result = MesDemarches::Client.query(MesDemarches::Queries::Dossier,
                                        variables: { dossier: dossier_number })
    dossier = (data = result.data) ? data.dossier : nil
    yield dossier
    Rails.logger.error(result.errors.values.join(',')) unless data
  end

  def create_controls(procedure)
    procedure['controles'].flatten.map.with_index do |description, i|
      description.map do |taskname, params|
        control = Object.const_get(taskname.camelize).new(params)
        control.name = "#{i}:#{taskname}"
        control
      end
    end.flatten
  end

  def check_updated_dossiers(controls)
    [*@procedure['demarches']].each do |demarche_number|
      reset = reset?(demarche_number, controls)
      check_demarche(controls, demarche_number, reset, @procedure['name'])
    end
  end

  def reset?(demarche_number, controls)
    counts = controls.map { |c| Check.where(demarche_id: demarche_number, checker: c.name).count }
    counts.uniq.size > 1
  end

  def check_demarche(controls, demarche_number, reset, configuration_name)
    demarche = DemarcheActions.get_demarche(demarche_number, configuration_name, @instructeur_email)
    set_demarche(controls, demarche_number)
    start_time = Time.zone.now
    since = reset ? EPOCH : demarche.checked_at
    DossierActions.on_dossiers(demarche.id, since) do |dossier|
      check_dossier(demarche, dossier, controls)
    end
    demarche.checked_at = start_time
    demarche.save
  end

  def set_demarche(controls, demarche_number)
    controls.each { |c| c.demarche_number = demarche_number }
  end

  def check_failed_dossiers(controls)
    Rails.logger.tagged('failed') do
      demarches = [*@procedure['demarches']]
      Check
        .where(failed: true, demarche: demarches)
        .select(:dossier, :demarche_id)
        .distinct.each do |check|
        on_dossier(check.dossier) do |md_dossier|
          check_dossier(check.demarche, md_dossier, controls)
        end
      end
    end
  end

  def check_updated_controls(controls)
    Rails.logger.tagged('updated control') do
      conditions = controls.map do |control|
        Check
          .where.not(version: control.version)
          .where(checker: control.name)
      end
      conditions
        .reduce { |c1, c2| c1.or(c2) }
        .where(demarche: [*@procedure['demarches']])
        .includes(:demarche)
        .each do |check|
        on_dossier(check.dossier) do |dossier|
          if dossier.present?
            check_dossier(check.demarche, dossier, controls)
          else
            Check.where(dossier: check.dossier).destroy_all
          end
        end
      end
    end
  end

  def remove_check(control, dossier_nb)
    Check.find_by(dossier: dossier_nb, checker: control.name)&.destroy!
  end

  def check_dossier(demarche, md_dossier, controls)
    Rails.logger.tagged("#{demarche.id},#{md_dossier.number}") do
      checks = []
      @dossier_has_different_messages = false
      @second_time = false
      failed_checks = false

      controls.each do |control|
        check = check_control(control, demarche, md_dossier)
        checks << check
        failed_checks ||= check.failed
      end
      unless failed_checks
        inform(md_dossier, checks)
        when_ok(demarche, md_dossier, checks) if @procedure['when_ok']
      end
    end
  end

  def check_control(control, demarche, md_dossier)
    Rails.logger.tagged(control.name) do
      check = find_or_create_check(control, demarche, md_dossier)
      start_time = Time.zone.now
      if check_obsolete?(check, control, md_dossier)
        apply_control(control, md_dossier, check) if control.must_check?(md_dossier)
        check.update(checked_at: start_time, version: control.version)
      end
      check
    end
  end

  def check_obsolete?(check, control, md_dossier)
    check.failed ||
      check.checked_at < DateTime.parse(md_dossier.date_derniere_modification) ||
      check.version != control.version.to_f
  end

  def find_or_create_check(control, demarche, md_dossier)
    # tmp code to ensure migration of old checker names
    check = Check.find_by(dossier: md_dossier.number, checker: control.name)
    old_check = Check.find_by(dossier: md_dossier.number, checker: control.old_name)
    if old_check.present?
      if check.present?
        old_check.destroy
      elsif old_check.present? && check.blank?
        old_check.update(checker: control.name)
      end
    end
    check ||
      Check.find_or_create_by(dossier: md_dossier.number, checker: control.name) do |c|
        c.checked_at = EPOCH
        c.demarche = demarche
        @dossier_has_different_messages = true # new check implies a message must be sent even if no error msg is triggered
      end
  end

  def when_ok(demarche, md_dossier, checks)
    message_nb = checks.flat_map(&:messages).size
    if message_nb.zero?
      ok_tasks.each do |task|
        task.process(demarche, md_dossier) if task.valid?
      end
    end
  end

  def ok_tasks
    @ok_tasks ||= @procedure['when_ok'].map do |task|
      if task.is_a?(String)
        Object.const_get(task.camelize).new({})
      else
        # hash
        task.map { |taskname, params| Object.const_get(taskname.camelize).new(params) }
      end
    end.flatten
  end

  def apply_control(control, md_dossier, check)
    check.failed = !control.valid?
    if control.valid?
      control.control(md_dossier)
      update_check_messages(check, control)
      @second_time ||= check.checked_at > EPOCH
    end
  rescue StandardError => e
    check.failed = true
    Rails.logger.error(e)
    Rails.logger.debug(e.backtrace)
  end

  NOMS_PIECES_MESSAGES = %i[debut_premier_mail debut_second_mail entete_anomalies entete_anomalie tout_va_bien fin_mail].freeze

  def get_pieces_messages(procedure_name, procedure)
    result = procedure['pieces_messages']
    raise ArgumentError, "#{procedure_name} devrait définir une section pieces_messages" if result.empty?

    result.symbolize_keys!
    missing = NOMS_PIECES_MESSAGES.reject { |nom| result.key?(nom) }
    raise ArgumentError, "#{procedure_name} devrait définir les libelles #{missing.join(',')}" if missing.present?

    result
  end

  def update_check_messages(check, task)
    old_messages = Set[check.messages.map(&:hashkey)]
    new_messages = Set[task.messages.map(&:hashkey)]
    return if old_messages == new_messages

    check.messages.destroy(check.messages.reject { |m| new_messages.include?(m.hashkey) })
    check.messages << task.messages.reject { |m| old_messages.include?(m.hashkey) }
    check.posted = false
    @dossier_has_different_messages = true
  end

  def inform(md_dossier, checks)
    if @dossier_has_different_messages
      instructeur_id = checks.first.demarche.instructeur
      messages = checks.flat_map(&:messages)
      inform_instructeur(md_dossier, instructeur_id, messages) if @inform_annotation.present?
      if @send_messages
        inform_user(md_dossier, instructeur_id, messages)
        checks.each { |check| check.update(posted: true) }
      end
    end
  end

  def inform_instructeur(md_dossier, instructeur_id, messages)
    if SetAnnotationValue.set_value(md_dossier, instructeur_id, @inform_annotation, messages.present?)
      # modified dossier ==> prevent next checking to consider the document is updated
      Check.where(dossier: md_dossier.number).update_all(checked_at: Time.zone.now)
    end
  end

  def inform_user(md_dossier, instructeur_id, messages)
    debut_mail = "<p>#{@pieces_messages[@second_time ? :debut_second_mail : :debut_premier_mail]}</p>"
    anomalies = liste_anomalies(md_dossier, messages)
    fin_mail = "<p>#{@pieces_messages[:fin_mail]}</p>"
    body = debut_mail + anomalies + fin_mail
    md_send_message(md_dossier.id, instructeur_id, body)
  end

  def get_annotation(md_dossier, name)
    md_dossier.annotations.find { |champ| champ.label == name }
  end

  def liste_anomalies(md_dossier, anomalies)
    msg_key = case anomalies.size
    when 0
      :tout_va_bien
    when 1
      :entete_anomalie
    else
      :entete_anomalies
    end
    entete_anomalies = "<p>#{@pieces_messages[msg_key]}</p>"

    anomalie_table = '<table class="table table-striped">' + anomalies.map do |a|
      '<tr>' \
        '<td>' + a.field + '</td>' \
        '<td>' + a.value + '</td>' \
        '<td>' + a.message + '</td>' \
        '</tr>'
    end.join("\n") + '</table>'
    fin_anomalie = anomalies.empty? ? '' : @pieces_messages[:fin_anomalie].gsub(/--dossier--/, modifier_url(md_dossier))
    entete_anomalies + anomalie_table + fin_anomalie
  end

  def modifier_url(md_dossier)
    ENV['GRAPHQL_HOST'] + "/dossiers/#{md_dossier.number}/modifier"
  end

  def md_send_message(dossier_id, instructeur_id, body)
    result = MesDemarches::Client.query(MesDemarches::Mutation::EnvoyerMessage,
                                        variables: {
                                          dossierId: dossier_id,
                                          instructeurId: instructeur_id,
                                          body: body,
                                          clientMutationId: 'dededed'
                                        })
    Rails.logger.error(result.errors.map(&:message).join(',')) if result.errors&.present?
  end
end
