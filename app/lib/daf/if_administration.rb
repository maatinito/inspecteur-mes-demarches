# frozen_string_literal: true

module Daf
  class IfAdministration < FieldChecker
    DATA_DIR = 'storage/if_administration'

    def version
      super + 1
    end

    def required_fields
      super + %i[taches]
    end

    def initialize(params)
      super
      @administration_naf = '8411Z'
      @tasks = InspectorTask.create_tasks(@params[:taches])
      FileUtils.mkdir_p(DATA_DIR)
    end

    def process(demarche, dossier)
      super
      return unless administration?

      process_tasks(demarche, dossier)
    end

    private

    def process_tasks(demarche, dossier)
      @tasks.each do |task|
        task.process(demarche, dossier) if task.valid? && task.must_check?(dossier)
        dossier = DossierActions.on_dossier(dossier.number) if task.updated_dossiers.find { |d| d.number == dossier.number }.present?
      rescue StandardError => e
        Sentry.capture_exception(e) if Rails.env.production?
        Rails.logger.error(e)
        e.backtrace.select { |b| b.include?('/app/') }.first(7).each { |b| Rails.logger.error(b) }
      end
    end

    def administration?
      company = field('Numéro Tahiti').etablissement
      return false unless company.present? && company.naf.split(' | ').any? { |naf| @administration_naf == naf }

      user_email = @dossier.usager.email
      case annotation('Agent administratif')&.value
      when 'Non'
        remove_user(user_email)
        return false
      when 'Oui'
        add_valid_user(user_email)
        return true
      end
      valid_users.include?(user_email)
    end

    def read_valid_users
      filename = valid_user_file
      return Set.new unless File.exist?(filename)

      YAML.load_file(filename, permitted_classes: [Set])
    end

    def valid_user_file
      "#{DATA_DIR}/valid_users.yml"
    end

    def valid_users
      @valid_users ||= read_valid_users
    end

    def add_valid_user(email)
      File.write(valid_user_file, YAML.dump(valid_users)) if valid_users.add?(email)
    end

    def remove_user(_user_email)
      File.write(valid_user_file, YAML.dump(valid_users)) if valid_users.delete(email)
    end
  end
end
