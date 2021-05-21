# frozen_string_literal: true

# Preview all emails at http://localhost:3000/rails/mailers/notification_mailer
class NotificationMailerPreview < ActionMailer::Preview
  def unauthorized_decision
    traitement = { instructeurEmail: 'rapetou@corp.com', state: 'refuse' }

    NotificationMailer.with(dossier: 78_748, demarche: 1054, traitement: traitement).unauthorized_decision
  end
end
