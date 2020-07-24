# frozen_string_literal: true

class InspectJob < CronJob
  self.schedule_expression = 'every 10 minute'

  def perform(*_args)
    VerificationService.new.check
  end
end
