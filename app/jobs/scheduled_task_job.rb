# frozen_string_literal: true

class ScheduledTaskJob < CronJob
  # self.schedule_expression = 'every day at noon'
  self.schedule_expression = 'every 2 minute'

  def perform
    # date_arel = ScheduledTask.arel_table[:run_at]
    #   .where(date_arel.lteq(Date.today))
    ScheduledTask.all.each do |scheduled|
      Rails.logger.tagged(scheduled.task) do
        task = InspectorTask.create_tasks([{ scheduled.task => JSON.parse(scheduled.parameters) }]).first
        DossierActions.on_dossier(scheduled.dossier) do |dossier|
          Rails.logger.tagged("#{dossier.demarche.number},#{dossier.number}") do
            demarche = Demarche.find(dossier.demarche.number)
            task.process(demarche, dossier)
          end
        end
        scheduled.destroy
      rescue StandardError => e
        Rails.logger.error("Error processing #{scheduled.task}: #{e.message}")
        e.backtrace.select { |b| b.include?('/app/') }.first(7).each { |b| Rails.logger.debug(b) }
      end
    end
  end

  def max_attempts
    1
  end
end
