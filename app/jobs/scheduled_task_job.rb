# frozen_string_literal: true

class ScheduledTaskJob < CronJob
  # self.schedule_expression = 'every day at 7:00'
  self.schedule_expression = ENV.fetch(SCHEDULEDTASK_CRON, 'every day at 6:00')

  def perform
    date_arel = ScheduledTask.arel_table[:run_at]
    date = Rails.env.development? ? 1.year.since.to_date : Date.today
    ScheduledTask.where(date_arel.lteq(date)).each do |scheduled|
      Rails.logger.tagged(scheduled.task) do
        task = InspectorTask.create_tasks([{ scheduled.task => JSON.parse(scheduled.parameters) }]).first
        throw "Impossible d'initialiser la tache #{scheduled.task}: #{task.errors.join(',')}" unless task.valid?

        perform_task(scheduled, task)
        scheduled.destroy
      rescue StandardError => e
        Sentry.capture_exception(e)
        Rails.logger.error("Error processing #{scheduled.task}: #{e.message}")
        e.backtrace.select { |b| b.include?('/app/') }.first(7).each { |b| Rails.logger.debug(b) }
      end
    end
  end

  def max_attempts
    1
  end

  private

  def perform_task(scheduled, task)
    DossierActions.on_dossier(scheduled.dossier) do |dossier|
      Rails.logger.tagged("#{dossier.demarche.number},#{dossier.number}") do
        demarche = Demarche.find(dossier.demarche.number)
        task.process(demarche, dossier)
      end
    end
  end
end
