# frozen_string_literal: true

class NotificationMailer < ApplicationMailer
  def unauthorized_decision
    @dossier = params[:dossier]
    @demarche = params[:demarche]
    @dossier_url = [ENV['GRAPHQL_HOST'], 'procedures', @demarche, 'dossiers', @dossier].join('/')
    @recipients = recipients
    @instructeur = params[:instructeur]
    @action = params[:state]
    throw 'instructeur parameter required' if @instructeur.nil?
    throw 'state parameter required' if @action.nil?

    mail(to: recipients, from: ENV['CONTACT_EMAIL'],
         subject: "#{SITE_NAME}: Instructeur non répertorié sur dossier #{@dossier}")
  end

  private

  def recipients
    params[:recipients] || ENV['CONTACT_EMAIL']
  end
end
