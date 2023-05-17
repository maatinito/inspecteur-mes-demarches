# frozen_string_literal: true

module Daf
  class RejectInvalidFiles < FieldChecker
    def version
      super + 1
    end

    def required_fields
      super + %i[champ max quand_invalide]
    end

    def authorized_fields
      super + %i[message]
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
      check_count do
        @when_invalid.each do |task|
          Rails.logger.info("Applying task #{task.class.name}")
          task.process(@demarche, @dossier)
        end
      end
    end

    def check(_dossier)
      super
      check_count do |count|
        add_message(@params[:champ], count, @params[:message])
      end
    end

    private

    def check_count
      repetition = field(@params[:champ])
      raise "Impossible de trouver le champ #{@params[:champ]} sur le dossier #{@dossier&.number}" if repetition.blank?

      label = repetition&.champs&.first&.label
      count = repetition.champs&.reduce(0) { |c, champ| champ.label == label ? c + 1 : c }
      max = @params[:max].to_i
      yield count if count > max
    end
  end
end
