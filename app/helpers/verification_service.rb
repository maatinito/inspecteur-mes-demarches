# frozen_string_literal: true

class VerificationService
  attr_reader :messages

  @@config = nil

  def check
    # http = MesDemarches.http("https://www.mes-demarches.gov.pf")
    # pp http
    # http = MesDemarches.http("https://www.mes-demarches.gov.pf")
    # pp http
    VerificationService.config.filter { |_k, d| d.key? 'demarches' }.each do |procedure_name, procedure|
      @pieces_messages = get_pieces_messages(procedure_name, procedure)
      @instructeur_email = instructeur_email(procedure)
      @send_messages = procedure['messages_automatiques']
      procedure['name'] = procedure_name
      controls = create_controls(procedure)
      check_updated_dossiers(controls, procedure)
      check_failed_dossiers(controls)
      check_updated_controls(controls)
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
        send_message(md_dossier, checks)
      end
    end
  end

  private

  EPOCH = Time.zone.parse('2000-01-01 00:00')

  def instructeur_email(procedure)
    result = procedure['email_instructeur']
    if result.empty?
      raise ArgumentError, "#{procedure_name} devrait définir 'email_instructeur' pour définir qui poste les messages aux usagers"
    end

    result
  end

  def on_dossiers(demarche, reset)
    start_time = Time.zone.now
    cursor = nil
    since = reset ? EPOCH : demarche.checked_at
    begin
      response = MesDemarches::Client.query(MesDemarches::Queries::DossiersModifies,
                                            variables: {
                                              demarche: demarche.id,
                                              since: since.iso8601,
                                              cursor: cursor
                                            })

      unless (data = response.data)
        throw StandardError.new "La démarche #{demarche_number} est introuvable #{ENV['GRAPHQL_HOST']}: #{response.errors.values.join(',')}"
      end

      dossiers = data.demarche.dossiers
      dossiers.nodes.each do |dossier|
        yield dossier if dossier.present?
      end
      page_info = dossiers.page_info
      cursor = page_info.end_cursor
    end while page_info.has_next_page
    demarche.checked_at = start_time
    demarche.save
  end

  def on_dossier(dossier_number)
    result = MesDemarches::Client.query(MesDemarches::Queries::Dossier,
                                        variables: { dossier: dossier_number })
    pp result.to_h
    dossier = (data = result.data) ? data.dossier : nil
    yield dossier
    Rails.logger.error(result.errors.values.join(',')) unless data
  end

  def create_controls(procedure)
    procedure['controles'].flatten.map do |control|
      control.map { |taskname, params| Object.const_get(taskname.camelize).new(params) }
    end.flatten
  end

  def check_updated_dossiers(controls, procedure)
    reset = controls.find { |control| Check.find_by_checker(control.class.name.underscore).nil? }.present?
    [*procedure['demarches']].each do |demarche_number|
      demarche = find_or_create_demarche(demarche_number, procedure)
      on_dossiers(demarche, reset) do |dossier|
        process_dossier(demarche, dossier, controls)
      end
    end
  end

  def check_failed_dossiers(controls)
    Check.where(failed: true)
         .includes(:demarche)
         .find_each do |check|
      on_dossier(check.dossier) do |md_dossier|
        process_dossier(check.demarche, md_dossier, controls)
      end
    end
  end

  def check_updated_controls(controls)
    controls.map do |control|
      Check
        .where.not(version: control.version)
        .where(checker: control.class.name.underscore)
        .includes(:demarche)
        .find_each do |check|
        on_dossier(check.dossier) do |dossier|
          if dossier.present?
            process_dossier(check.demarche, dossier, controls)
          else
            check.destroy!
          end
        end
      end
    end
  end

  def find_or_create_demarche(demarche_number, procedure)
    result = MesDemarches::Client.query(MesDemarches::Queries::Demarche,
                                        variables: { demarche: demarche_number })
    gql_demarche = result.data.demarche
    demarche = Demarche.find_or_create_by(id: demarche_number) do |d|
      d.checked_at = EPOCH
    end
    demarche.libelle = gql_demarche.title
    demarche.configuration = procedure['name']
    gql_instructeur = gql_demarche.groupe_instructeurs.flat_map(&:instructeurs).find { |i| i.email == @instructeur_email }
    if gql_instructeur.nil?
      throw StandardError.new "Aucun instructeur #{@instructeur.email} sur la demarche #{demarche_number}"
    end
    demarche.instructeur = gql_instructeur.id
    demarche.save!
    demarche
  end

  def process_dossier(demarche, md_dossier, controls)
    if md_dossier.state == 'en_construction'
      check_dossier(demarche, md_dossier, controls)
    else
      remove_checks(md_dossier.number)
    end
  end

  def remove_checks(dossier_nb)
    Check.find_by_dossier(dossier_nb)&.destroy!
  end

  def check_dossier(demarche, md_dossier, controls)
    checks = []
    @dossier_has_different_messages = false
    @second_time = false

    controls.each do |control|
      next unless control.valid?

      check = Check.find_or_create_by(dossier: md_dossier.number, checker: control.class.name.underscore) do |c|
        c.checked_at = EPOCH
        c.demarche = demarche
      end
      start_time = Time.zone.now
      if check.checked_at < md_dossier.date_derniere_modification || check.version < control.version
        apply_control(control, md_dossier, check)
      end
      check.checked_at = start_time
      check.save
      checks << check
    end
    send_message(md_dossier, checks) if @dossier_has_different_messages && @send_messages
  end

  def apply_control(control, dossier, check)
    control.control(dossier)
    update_check_messages(check, control)
    @second_time ||= check.checked_at > EPOCH
    check.failed = false
    check.version = control.version
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

  def send_message(md_dossier, checks)
    debut_mail = "<p>#{@pieces_messages[@second_time ? :debut_second_mail : :debut_premier_mail]}</p>"
    anomalies = liste_anomalies(checks)
    fin_mail = "<p>#{@pieces_messages[:fin_mail]}</p>"
    body = debut_mail + anomalies + fin_mail
    instructeur_id = checks.first.demarche.instructeur
    dossier_id = md_dossier.id
    checks.each do |check|
      check.posted = true
      check.save
    end

    send_message_to_md(dossier_id, instructeur_id, body)
  end

  def liste_anomalies(checks)
    anomalies = checks.flat_map(&:messages)
    entete_anomalies = "<p>#{@pieces_messages[case anomalies.size
                                              when 0
                                                :tout_va_bien
                                              when 1
                                                :entete_anomalie
                                              else
                                                :entete_anomalies
                                              end]}</p>"

    anomalie_table = '<table class="table table-striped">' + anomalies.map do |a|
      '<tr>' \
        '<td>' + a.field + '</td>' \
        '<td>' + a.value + '</td>' \
        '<td>' + a.message + '</td>' \
        '</tr>'
    end.join("\n") + '</table>'
    fin_anomalie = !anomalies.empty? ? @pieces_messages[:fin_anomalie] : ''
    entete_anomalies + anomalie_table + fin_anomalie
  end

  def send_message_to_md(dossier_id, instructeur_id, body)
    puts "Dossier #{dossier_id}: instruit par #{instructeur_id} #{body}"
    MesDemarches::Client.query(MesDemarches::Mutation::EnvoyerMessage,
                               variables: {
                                 dossierId: dossier_id,
                                 instructeurId: instructeur_id,
                                 body: body,
                                 clientMutationId: 'dededed'
                               })
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
end
