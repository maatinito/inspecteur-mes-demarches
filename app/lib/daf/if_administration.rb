# frozen_string_literal: true

module Daf
  class IfAdministration < FieldChecker
    DATA_DIR = 'storage/if_administration'
    ADMINISTRATION_NAF = '84'

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
      @check_validation = Set['oui', 'true', '1', 1].include?(@params[:confirmation]&.downcase)
      @tasks = InspectorTask.create_tasks(@params[:taches])
      FileUtils.mkdir_p(DATA_DIR)
    end

    def process(demarche, dossier)
      super
      return unless administration?

      process_tasks(demarche, dossier)
    end

    def administration_naf?
      company = field('Numéro Tahiti')&.etablissement
      administration = company.present? && company.naf.split(' | ').any? { |naf| naf&.start_with?(ADMINISTRATION_NAF) }
      Rails.logger.info("Numéro Tahiti with naf #{company&.naf} designate administration : #{administration}")
      administration
    end

    def daf?
      daf = fields('Administration')&.any? { |champ| champ.value.present? }
      Rails.logger.info("DAF : #{daf}")
      daf
    end

    def verified?
      administrative_agent = annotation('Agent administratif')&.value == 'Oui'
      Rails.logger.info("Vérification Agent administratif ==> #{administrative_agent}")
      administrative_agent
    end

    private

    def process_tasks(demarche, dossier)
      @tasks.each do |task|
        task.process(demarche, dossier) if task.valid? && task.must_check?(dossier)
        dossier = DossierActions.on_dossier(dossier.number) if task.updated_dossiers.find { |d| d.number == dossier.number }.present?
      end
    end

    def administration?
      return false unless administration_naf? || daf?

      !@check_validation || verified?
    end
  end
end
