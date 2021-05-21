# frozen_string_literal: true

module Instruction
  class DecisionChecker < FieldChecker
    def version
      super + 3
    end

    DECISIONS = Set['accepte', 'refuse', 'classe_sans_suite']
    DEFAULT_DECISIONS = 'accepte,refuse,classe_sans_suite'
    SPLIT = /[\s,]/.freeze

    def must_check?(md_dossier)
      @authorized_decisions.include?(md_dossier&.state)
    end

    def required_fields
      super + %i[instructeurs_autorises qui_alerter]
    end

    def authorized_fields
      super + %i[decisions_autorisees]
    end

    def initialize(params)
      super
      decisions = @params[:decisions_autorisees]
      decisions ||= decisions_par_defaut
      @authorized_decisions = Set.new(decisions.map(&:strip))
      invalid_decisions = @authorized_decisions.reject { |d| DECISIONS.include?(d) }
      @errors << "#{invalid_decisions.join(',')} ne sont pas des état de dossier valide" if invalid_decisions.present?

      @authorized_instructors = Set.new(@params[:instructeurs_autorises]&.map(&:strip))
      @errors << "Aucun instructeur possible pour le ou les decisions '#{@authorized_decisions&.join(',')}'" if @authorized_instructors.empty?

      @alert_emails = @params[:qui_alerter]&.map(&:strip)
    end

    def check(dossier)
      traitements = dossier&.traitements
      return if traitements.blank?

      last_decision = traitements.max_by(&:processed_at)
      return if @authorized_instructors.include? last_decision.instructeur_email

      NotificationMailer.with(demarche: @demarche.id,
                              dossier: dossier.number,
                              instructeur: last_decision.instructeur_email,
                              state: last_decision.state,
                              recipients: @alert_emails)
                        .unauthorized_decision.deliver_later
    end
  end
end
