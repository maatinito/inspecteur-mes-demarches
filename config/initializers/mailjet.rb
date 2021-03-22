# frozen_string_literal: true

Mailjet.configure do |config|
  config.api_key = Rails.application.secrets.mailjet[:api_key]
  config.secret_key = Rails.application.secrets.mailjet[:secret_key]
  config.default_from = ENV.fetch('CONTACT_EMAIL', "mes-demarches#{64.chr}modernisation.gov.pf")
  config.api_version = 'v3.1'
end
