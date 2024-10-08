# frozen_string_literal: true

class NotificationMailer < ApplicationMailer
  def unauthorized_decision
    @dossier = params[:dossier]
    @demarche = params[:demarche]
    @dossier_url = [ENV.fetch('GRAPHQL_HOST', nil), 'procedures', @demarche, 'dossiers', @dossier].join('/')
    @recipients = recipients
    @instructeur = params[:instructeur]
    @action = params[:state]
    raise 'instructeur parameter required' if @instructeur.nil?
    raise 'state parameter required' if @action.nil?

    mail(to: recipients, subject: "#{SITE_NAME}: Instructeur non répertorié sur dossier #{@dossier}")
  end

  def report_error
    @dossier = params[:dossier]
    @demarche = params[:demarche]
    @dossier_url = [ENV.fetch('GRAPHQL_HOST', nil), 'procedures', @demarche, 'dossiers', @dossier].join('/') if @dossier.present? && @demarche.present?
    @tags = params[:tags]
    @message = params[:message]
    @backtrace = params[:backtrace]&.select { |b| b.include?('/app/') }&.first(7) || []
    Rails.logger.error(message)
    @backtrace.each { |b| Rails.logger.error(b) }
    mail(to: TECH_EMAIL, subject: "#{SITE_NAME}: erreur à l'exécution")
  end

  def notify_user
    @dossier = params[:dossier]
    @demarche = params[:demarche]
    @dossier_url = [ENV.fetch('GRAPHQL_HOST', nil), 'procedures', @demarche, 'dossiers', @dossier].join('/') if @dossier.present? && @demarche.present?
    @message = params[:message].gsub(/\n\r?/, "<br>\n")
    attachments[params[:filename]] = params[:file] if params[:file] && params[:filename]
    mail(to: recipients, subject: "#{SITE_NAME}: #{params[:subject]}")
  end

  def user_mail
    @message = params[:message].gsub(/\n\r?/, "<br>\n")
    attachments[params[:filename]] = params[:file] if params[:file] && params[:filename]
    mail(to: recipients, subject: params[:subject]) do |format|
      format.html { render layout: 'md_mailer' } # Layout spécifique pour ce mail
    end
  end

  private

  def recipients
    params[:recipients] || TECH_EMAIL
  end
end
