# frozen_string_literal: true

# Preview all emails at http://localhost:3000/rails/mailers/notification_mailer
class NotificationMailerPreview < ActionMailer::Preview
  def unauthorized_decision
    task = Instruction::DecisionChecker.new({
                                              decisions_autorisees: %w[refuse accepte classer_sans_suite],
                                              instructeurs_autorises: %w[ok@corp.com],
                                              qui_alerter: %w[dircab@hc.com]
                                            })
    traitement = { instructeurEmail: 'rapetou@corp.com', state: 'refuse' }

    NotificationMailer.with(dossier: 78_748, demarche: 1054, traitement: traitement).unauthorized_decision
  end
end
