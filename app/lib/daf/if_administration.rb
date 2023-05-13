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

    def authorized_fields
      super + %i[confirmation]
    end

    def initialize(params)
      super
      @administration_naf = '8411Z'
      @check_validation = Set['oui', 'true', '1', 1].include?(@params[:confirmation]&.downcase)
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
      company = field('Numéro Tahiti')&.etablissement
      return false unless company.present? && company.naf.split(' | ').any? { |naf| @administration_naf == naf }

      !@check_validation || annotation('Agent administratif')&.value == 'Oui'
    end
  end
end
