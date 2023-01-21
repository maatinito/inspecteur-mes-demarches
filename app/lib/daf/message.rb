# frozen_string_literal: true

module Daf
  class Message < FieldChecker
    def version
      super + 1
    end

    def required_fields
      super + %i[message]
    end

    def authorized_fields
      super + %i[champ_telephone sms destinataires]
    end

    include Payzen::StringTemplate

    def initialize(params)
      super
      @mails = @params[:destinataires]
      @mails = @mails.split(/\s*,\s*/) if @mails.is_a?(String)
    end

    def process(demarche, dossier)
      super
      message = instanciate(@params[:message])
      if @mails.present?
        send_mail(demarche, dossier, message)
      else
        SendMessage.send(dossier, instructeur_id_for(demarche, dossier), message, check_not_sent: true)
      end
    end

    def send_mail(demarche, dossier, message)
      params = {
        subject: demarche.libelle,
        demarche: demarche.id,
        dossier: dossier.number,
        message:,
        recipients: @mails
      }
      NotificationMailer.with(params).notify_user.deliver_later
    end
  end
end
