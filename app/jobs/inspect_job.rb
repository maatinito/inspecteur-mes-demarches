# frozen_string_literal: true

class InspectJob < CronJob
  self.schedule_expression = 'every 6 minute'

  MANUAL_SYNC = 'ManualSync'

  def perform
    Sync.find_or_create_by(job: MANUAL_SYNC)
    Sync.find_or_create_by(job: self.class.name) do
      VerificationService.new.check
    end
  ensure
    Sync.where(job: self.class.name).destroy_all
    Sync.where(job: MANUAL_SYNC).destroy_all
  end

  def max_attempts
    1
  end

  def self.run
    Sync.find_or_create_by(job: MANUAL_SYNC) do
      InspectJob.perform_later
    end
  end

  def self.running?
    Sync.exists?(job: MANUAL_SYNC)
  end
end
