# frozen_string_literal: true

class ScheduledTaskJob < CronJob
  # self.schedule_expression = 'every day at 7:00'
  self.schedule_expression = ENV.fetch('SCHEDULEDTASK_CRON', '0-59 5-23 * * *')

  def perform
    datetime_arel = ScheduledTask.arel_table[:run_at]
    ScheduledTask.where(datetime_arel.lteq(Time.zone.now)).each do |scheduled|
      Rails.logger.tagged(scheduled.task) do
        task = InspectorTask.create_tasks([{ scheduled.task => JSON.parse(scheduled.parameters) }]).first
        raise "Impossible d'initialiser la tache #{scheduled.task}: #{task.errors.join(',')}" unless task.valid?

        Rails.logger.info("Processing Scheduled Task at #{scheduled.run_at} / #{Time.zone.now}")
        perform_task(scheduled, task)
        scheduled.destroy
      rescue StandardError => e
        Sentry.capture_exception(e)
        NotificationMailer.with(error_params("Error processing #{scheduled.task}", e)).report_error.deliver_later
      end
    end
  end

  def max_attempts
    1
  end

  private

  def error_params(message, exception)
    {
      message: "#{message} : #{exception.message}",
      backtrace: exception.backtrace,
      tags: Rails.logger.formatter.current_tags.join(',')
    }
  end

  def perform_task(scheduled, task)
    DossierActions.on_dossier(scheduled.dossier) do |dossier|
      Rails.logger.tagged("#{dossier.demarche.number},#{dossier.number}") do
        demarche = Demarche.find(dossier.demarche.number)
        task.process(demarche, dossier)
      end
    end
  end
end
