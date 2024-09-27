# frozen_string_literal: true

class SendMail < FieldChecker
  def version
    super + 1
  end

  def required_fields
    super + %i[destinataires objet message champ_envoi]
  end

  def initialize(params)
    super
    @mails = @params[:destinataires]
    @mails = @mails.split(/\s*,\s*/) if @mails.is_a?(String)
    @timestamp_field = @params[:champ_envoi]
  end

  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    last_sent = annotation(@timestamp_field)&.value
    return if last_sent.present?

    message = instanciate(@params[:message])
    subject = instanciate(@params[:objet])
    recipients = @mails.map(&method(:instanciate)).join(',')

    NotificationMailer.with({ subject:, message:, recipients: }).user_mail.deliver_later

    SetAnnotationValue.set_value(@dossier, demarche.instructeur, @timestamp_field, Time.zone.now.iso8601)
    dossier_updated(dossier)
  end
end
