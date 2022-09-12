# frozen_string_literal: true

class NotificationMailer < ApplicationMailer
  def unauthorized_decision
    @dossier = params[:dossier]
    @demarche = params[:demarche]
    @dossier_url = [ENV.fetch('GRAPHQL_HOST', nil), 'procedures', @demarche, 'dossiers', @dossier].join('/')
    @recipients = recipients
    @instructeur = params[:instructeur]
    @action = params[:state]
    throw 'instructeur parameter required' if @instructeur.nil?
    throw 'state parameter required' if @action.nil?

    mail(to: recipients, subject: "#{SITE_NAME}: Instructeur non répertorié sur dossier #{@dossier}")
  end

  def report_error
    @dossier = params[:dossier]
    @demarche = params[:demarche]
    @dossier_url = [ENV.fetch('GRAPHQL_HOST', nil), 'procedures', @demarche, 'dossiers', @dossier].join('/') if @dossier.present? && @demarche.present?
    @message = params[:message]
    @exception = params[:exception]
    mail(to: CONTACT_EMAIL, subject: "#{SITE_NAME}: erreur à l'exécution")
  end

  private

  def recipients
    params[:recipients] || CONTACT_EMAIL
  end
end
