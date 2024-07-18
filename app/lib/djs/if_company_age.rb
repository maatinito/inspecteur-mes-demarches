# frozen_string_literal: true

module Djs
  class IfCompanyAge < FieldChecker
    def version
      super + 1
    end

    def required_fields
      super + %i[]
    end

    def authorized_fields
      super + %i[champ age_max age_min quand_invalide message]
    end

    def initialize(params)
      super
      @when_invalid = InspectorTask.create_tasks(@params[:quand_invalide])
    end

    def must_check?(md_dossier)
      md_dossier&.state == 'en_construction' || md_dossier&.state == 'en_instruction'
    end

    def process(demarche, dossier)
      super
      check_age do
        @when_invalid.each do |task|
          Rails.logger.info("Applying task #{task.class.name}")
          task.process(@demarche, @dossier)
        end
      end
    end

    def check(_dossier)
      super
      check_age do |count|
        add_message(@params[:champ], count, @params[:message])
      end
    end

    private

    def check_age
      etablissement = @params[:champ].present? ? param_field(:champ)&.etablissement : @dossier.demandeur
      creation_date = Date.parse(etablissement&.entreprise&.date_creation.presence || '2000-01-01')
      years_passed = Time.zone.now.year - creation_date.year
      years_passed -= 1 if Time.zone.now < creation_date + years_passed.years
      upper_check = @params[:age_max].nil? || years_passed <= @params[:age_max].to_i
      lower_check = @params[:age_min].nil? || years_passed >= @params[:age_min].to_i
      yield years_passed unless lower_check && upper_check
    end
  end
end
