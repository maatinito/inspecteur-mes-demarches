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
      super + %i[destinataires champ_envoi]
    end

    include Payzen::StringTemplate

    def initialize(params)
      super
      @mails = @params[:destinataires]
      @mails = @mails.split(/\s*,\s*/) if @mails.is_a?(String)
      @timestamp_field = @params[:champ_envoi]
    end

    def process(demarche, dossier)
      super
      message = instanciate(@params[:message])

      # Instancier les emails avec les variables du dossier (supporte {Champ})
      mails = (@mails.map { |mail| instanciate(mail) }.compact.select(&:present?) if @mails.present?)

      if mails.present?
        send_mail(demarche, dossier, message, mails)
      else
        SendMessage.deliver_message(dossier, instructeur_id_for(demarche, dossier), message, check_not_sent: true)
      end
    end

    def send_mail(demarche, dossier, message, mails)
      if @timestamp_field
        last_sent = annotation(@timestamp_field)&.value
        return if sent_less_than_one_day_ago(last_sent)

        SetAnnotationValue.set_value(@dossier, @demarche.instructeur, @timestamp_field, Time.zone.now.iso8601)
        dossier_updated(dossier)
      end
      params = {
        subject: demarche.libelle,
        demarche: demarche.id,
        dossier: dossier.number,
        message:,
        recipients: mails
      }
      NotificationMailer.with(params).notify_user.deliver_later
    end

    private

    def sent_less_than_one_day_ago(last_sent)
      last_sent.present? && Time.zone.now - Time.zone.parse(last_sent) < 1.day
    rescue StandardError
      false
    end
  end
end
