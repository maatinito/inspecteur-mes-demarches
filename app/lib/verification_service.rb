# frozen_string_literal: true

class VerificationService
  attr_reader :messages, :user_email

  @@config = nil
  @@network_error_notified = {}
  NETWORK_ERROR_COOLDOWN = 1.hour

  def initialize(user_email = nil)
    @user_email = user_email
  end

  def check
    return unless DemarcheActions.ping

    VerificationService.configs.each do |filename, data|
      Rails.logger.tagged(File.basename(filename)) do
        data.filter { |_k, d| d.key? 'demarches' }.each do |procedure_name, procedure|
          Rails.logger.tagged(procedure_name) do
            @pieces_messages = get_pieces_messages(procedure_name, procedure)
            @instructeur_email = instructeur_email(procedure)
            @send_messages = procedure['messages_automatiques']
            @inform_annotation = procedure['annotation_information']
            procedure['name'] = procedure_name
            @procedure = procedure
            create_controls
            create_when_ok_tasks
            check_updated_dossiers(@controls)
            check_failed_dossiers(@controls)
            check_updated_controls(@controls)
          end
        rescue StandardError => e
          raise e unless Rails.env.production?

          report_error('Error processing demarche', e)
        end
      end
    end
  end

  def error_params(message, exception)
    {
      message: "#{message} : #{exception.message}",
      backtrace: exception.backtrace,
      tags: Rails.logger.formatter.current_tags.join(',')
    }
  end

  def report_error(message, exception)
    return unless should_notify_error?(message, exception)

    NotificationMailer.with(error_params(message, exception)).report_error.deliver_later
    mark_error_notified(message, exception)
  end

  def should_notify_error?(message, exception)
    return true unless network_error?(exception)

    error_key = network_error_key(message, exception)
    last_notification = @@network_error_notified[error_key]

    last_notification.nil? || last_notification < NETWORK_ERROR_COOLDOWN.ago
  end

  def mark_error_notified(message, exception)
    return unless network_error?(exception)

    error_key = network_error_key(message, exception)
    @@network_error_notified[error_key] = Time.current
  end

  def network_error?(exception)
    network_error_patterns = [
      /connection/i,
      /timeout/i,
      /network/i,
      /host/i,
      /resolve/i,
      /refused/i,
      /unreachable/i,
      /socket/i
    ]

    error_message = exception.message.to_s
    network_error_patterns.any? { |pattern| error_message.match?(pattern) }
  end

  def network_error_key(message, exception)
    "#{message}_#{exception.class.name}".downcase.gsub(/[^a-z0-9_]/, '_')
  end

  def self.clear_network_error_notifications
    @@network_error_notified.clear
  end

  def post_message(dossier_number)
    graphql = MesDemarches.query(MesDemarches::Queries::DossierId,
                                 variables: { number: dossier_number })
    if graphql.data.dossier?
      md_dossier = graphql.data.dossier
      checks = Check.where(dossier: dossier_number).all
      if checks.present? && md_dossier.present?
        demarche = checks.first.demarche_id
        VerificationService.configs.each_value.filter { |_k, d| (d.key? 'demarches') && d['demarches'].include?(demarche) }.each do |procedure_name, procedure|
          @pieces_messages = get_pieces_messages(procedure_name, procedure)
        end
        inform(md_dossier, checks)
      end
    end
  end

  def self.config_file_name
    @@config_file_name ||= Rails.root.join('storage', 'auto_instructeur.yml')
  end

  def self.file_manager
    @@files ||= if Rails.env.production? && ENV.fetch('FILE_MANAGER', 'S3') == 'S3'
                  Tools::S3FileManager.new(
                    ENV.fetch('S3_BUCKET', nil),
                    access_key_id: Rails.application.secrets.s3[:access_key_id],
                    secret_access_key: Rails.application.secrets.s3[:secret_access_key],
                    endpoint: ENV.fetch('S3_ENDPOINT', nil),
                    region: ENV.fetch('S3_REGION', nil)
                  )
                else
                  Tools::DiskFileManager.new('storage')
                end
  end

  def self.configs
    file_manager.configurations
  end

  private

  EPOCH = Time.zone.parse('2000-01-01 00:00')

  def instructeur_email(procedure)
    result = procedure['email_instructeur']
    raise ArgumentError, "#{procedure_name} devrait définir 'email_instructeur' pour définir qui poste les messages aux usagers" if result.empty?

    result
  end

  def on_dossier(dossier_number)
    result = MesDemarches.query(MesDemarches::Queries::Dossier,
                                variables: { dossier: dossier_number })
    dossier = (data = result.data) ? data.dossier : nil
    yield dossier
    Rails.logger.error(result.errors.values.join(',')) unless data
  end

  def create_controls
    @controls = InspectorTask.create_tasks(@procedure['controles'])
  end

  def check_updated_dossiers(controls)
    [*@procedure['demarches']].each do |demarche_number|
      Rails.logger.tagged(demarche_number) do
        reset = reset?(demarche_number, controls)
        check_demarche(controls, demarche_number, reset, @procedure['name'])
      end
    end
  end

  def reset?(demarche_number, controls)
    counts = controls.map { |c| Check.where(demarche_id: demarche_number, checker: c.name).count }
    counts.uniq.size > 1
  end

  def check_demarche(controls, demarche_number, reset, configuration_name)
    Rails.logger.info("Processing procedure #{demarche_number}")
    demarche = DemarcheActions.get_demarche(demarche_number, configuration_name, @instructeur_email)

    # Vérifier si l'utilisateur courant est autorisé à traiter cette démarche
    unless current_user_has_access_to?(demarche)
      Rails.logger.info("Procedure #{demarche_number} ignored as user #{@user_email} doesn't handle it.")
      return
    end

    set_demarche(controls, demarche)
    start_time = Time.zone.now
    since = reset ? EPOCH : demarche.checked_at
    DossierActions.on_dossiers(demarche.id, since) do |dossier|
      check_dossier(demarche, dossier, controls)
    end
    demarche.checked_at = start_time
    demarche.save
  end

  def current_user_has_access_to?(demarche)
    # Vérifier si l'utilisateur est un instructeur de la démarche par son email
    return true if @user_email.blank?

    demarche.instructeurs.exists?(email: @user_email)
  end

  def set_demarche(controls, demarche)
    controls.each { |c| c.demarche = demarche }
  end

  def check_failed_dossiers(controls)
    Rails.logger.tagged('failed') do
      failed_checks.each do |check|
        # Vérifier si l'utilisateur est autorisé à traiter cette démarche
        unless current_user_has_access_to?(check.demarche)
          Rails.logger.info("User #{@user_email} is not authorized to process failed dossier #{check.dossier}")
          next
        end

        on_dossier(check.dossier) do |md_dossier|
          if md_dossier.present?
            check_dossier(check.demarche, md_dossier, controls)
          else
            remove_checks(check.dossier)
          end
        end
      end
    end
  end

  def remove_checks(dossier)
    Rails.logger.info('Dossier non concerné par les contrôles')
    Check.where(dossier:).destroy_all
  end

  def failed_checks
    Check
      .where(failed: true, demarche: [*@procedure['demarches']])
      .select(:dossier, :demarche_id)
      .distinct
  end

  def check_updated_controls(controls)
    Rails.logger.tagged('updated control') do
      obsolete_checks(controls + @ok_tasks).each do |check|
        # Vérifier si l'utilisateur est autorisé à traiter cette démarche
        unless current_user_has_access_to?(check.demarche)
          Rails.logger.info("User #{@user_email} is not authorized to process updated control for dossier #{check.dossier}")
          next
        end

        on_dossier(check.dossier) do |dossier|
          if dossier.present?
            check_dossier(check.demarche, dossier, controls)
          else
            remove_checks(check.dossier)
          end
        end
      end
    end
  end

  def obsolete_checks(controls)
    conditions = controls.map do |control|
      Check
        .where.not(version: control.version)
        .where(checker: control.name)
    end
    return [] unless conditions.present?

    conditions
      .reduce { |c1, c2| c1.or(c2) }
      .where(demarche: [*@procedure['demarches']])
      .includes(:demarche)
  end

  def remove_check(control, dossier_nb)
    Check.find_by(dossier: dossier_nb, checker: control.name)&.destroy!
  end

  def check_dossier(demarche, md_dossier, controls)
    Rails.logger.info("Processing dossier #{md_dossier.number}")
    Rails.logger.tagged(md_dossier.number) do
      affected = affected?(controls, md_dossier)
      if affected
        apply_controls(controls, demarche, md_dossier)
      else
        remove_checks(md_dossier.number)
      end
    end
  end

  def affected?(controls, md_dossier)
    [*controls, *@ok_tasks].find { |c| c.must_check?(md_dossier) }
  rescue StandardError => e
    raise e unless Rails.env.production?

    report_error('Error checking which task must be applied (must_check?)', e)
  end

  def apply_controls(controls, demarche, md_dossier)
    checks = []
    @dossier_has_different_messages = false
    @second_time = false
    failed_checks = false

    controls.each do |control|
      check = check_control(control, demarche, md_dossier)
      checks << check
      failed_checks ||= check.failed
      md_dossier = DossierActions.on_dossier(md_dossier.number) if control.dossier_updated?(md_dossier)
    end
    unless failed_checks
      inform(md_dossier, checks, send_message: @send_messages) if @dossier_has_different_messages
      when_ok(demarche, md_dossier, checks) if @ok_tasks.present?
    end
  end

  def check_control(control, demarche, md_dossier)
    Rails.logger.tagged(control.name) do
      check = find_or_create_check(control, demarche, md_dossier)
      start_time = Time.zone.now
      check_obsolete = check_obsolete?(check, control, md_dossier)
      Rails.logger.info("dossier or task version modified = #{check_obsolete}")
      if check_obsolete
        control_must_check = control.must_check?(md_dossier)
        Rails.logger.info("task ask for processing = #{control_must_check}")
        apply_control(control, md_dossier, check) if control_must_check
        check.update(checked_at: start_time, version: control.version)
        avoid_useless_checks(control)
        recheck_dependent_dossiers(control)
      end
      check
    end
  end

  def avoid_useless_checks(control)
    control.updated_dossiers.each do |dossier|
      next unless dossier.present?

      checked_at = Check.arel_table[:checked_at]
      checkers = Check.where(dossier: dossier.number)
                      .where(checked_at.gt(dossier.date_derniere_modification))
      Rails.logger.debug("Checkers : #{checkers.map(&:checker).join(',')}")
      checkers.update_all(checked_at: Time.zone.now)
    end
  end

  def recheck_dependent_dossiers(control)
    # tags associated checks to trigger recheck
    Check.where(dossier: control.dossiers_to_recheck).update_all(version: 0)
  end

  def check_obsolete?(check, control, md_dossier)
    check.failed ||
      check.checked_at < DateTime.parse(md_dossier.date_derniere_modification) ||
      check.version != control.version
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
    message_present = checks.any? { |c| c.messages.present? }
    unless message_present
      @ok_tasks.each do |task|
        Rails.logger.tagged(task.name) do
          check = Check.find_or_create_by(demarche:, dossier: md_dossier.number, checker: task.name)
          start_time = Time.zone.now
          apply_task(demarche, task, md_dossier, check)
          md_dossier = DossierActions.on_dossier(md_dossier.number) if task.dossier_updated?(md_dossier)
          check.update(checked_at: start_time, version: task.version)
        end
      end
    end
  end

  def create_when_ok_tasks
    @ok_tasks = InspectorTask.create_tasks(@procedure['when_ok'])
  end

  def apply_task(demarche, task, md_dossier, check)
    check.failed = !task.valid?
    task.process(demarche, md_dossier) if task.valid?
  rescue StandardError => e
    check.failed = true
    raise e unless Rails.env.production?

    report_error('Error applying task', e)
  end

  def apply_control(control, md_dossier, check)
    previous_failed = check.failed
    check.failed = !control.valid?
    if control.valid?
      control.control(md_dossier)
      update_check_messages(check, control)
      @second_time ||= check.checked_at > EPOCH
      # send message if previous check failed and new one is Ok
      @dossier_has_different_messages ||= !check.failed && previous_failed
    else
      puts "Task invalid #{control.name}: #{control.errors.join(',')}"
      NotificationMailer.with(message: "Task invalid #{control.name}: #{control.errors.join(',')}", tags: Rails.logger.formatter.current_tags.join(',')).report_error.deliver_later
    end
  rescue StandardError => e
    check.failed = true
    raise e unless Rails.env.production?

    report_error('Error applying control', e)
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
    old_messages = Set.new(check.messages.map(&:hashkey))
    new_messages = Set.new(task.messages.map(&:hashkey))
    return if old_messages == new_messages

    check.messages.destroy(check.messages.reject { |m| new_messages.include?(m.hashkey) })
    check.messages << task.messages.reject { |m| old_messages.include?(m.hashkey) }
    check.posted = false
    @dossier_has_different_messages = true
  end

  def inform(md_dossier, checks, send_message: true)
    instructeur_id = checks.first.demarche.instructeur
    messages = checks.flat_map(&:messages)
    inform_instructeur(md_dossier, instructeur_id, messages) if @inform_annotation.present?
    if send_message
      inform_user(md_dossier, instructeur_id, messages)
      checks.each { |check| check.update(posted: true) }
    end
  end

  def inform_instructeur(md_dossier, instructeur_id, messages)
    annotation = md_dossier.annotations.find { |champ| champ.label == @inform_annotation }
    raise "Unable to find information annotation named '#{@inform_annotation}'" if annotation.nil?

    value = if annotation.__typename == 'CheckboxChamp'
              messages.present?
            else
              messages.present? ? 'En erreur' : 'OK'
            end
    if SetAnnotationValue.set_value(md_dossier, instructeur_id, @inform_annotation, value)
      # modified dossier ==> prevent next checking to consider the document is updated
      Check.where(dossier: md_dossier.number).update_all(checked_at: Time.zone.now)
    end
  end

  def inform_user(md_dossier, instructeur_id, messages)
    debut_mail = "<p>#{@pieces_messages[@second_time ? :debut_second_mail : :debut_premier_mail]}</p>"
    anomalies = liste_anomalies(md_dossier, messages)
    fin_mail = "<p>#{@pieces_messages[:fin_mail]}</p>"
    body = debut_mail + anomalies + fin_mail
    SendMessage.send(md_dossier, instructeur_id, body)
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

    rows = anomalies.map do |a|
      '<tr>' \
      '<td>' + a.field + '</td>' \
                         '<td>' + a.value + '</td>' \
                                            '<td>' + a.message + '</td>' \
                                                                 '</tr>'
    end.join("\n")
    anomalie_table = "<table class=\"table table-striped\">#{rows}</table>"
    fin_anomalie = anomalies.empty? ? '' : @pieces_messages[:fin_anomalie].gsub('--dossier--', modifier_url(md_dossier))
    entete_anomalies + anomalie_table + fin_anomalie
  end

  def modifier_url(md_dossier)
    ENV.fetch('GRAPHQL_HOST', nil) + "/dossiers/#{md_dossier.number}/modifier"
  end
end
