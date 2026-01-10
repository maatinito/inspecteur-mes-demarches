# frozen_string_literal: true

Mailjet.configure do |config|
  config.api_key = ENV.fetch('MAILJET_API_KEY', nil)
  config.secret_key = ENV.fetch('MAILJET_SECRET_KEY', nil)
  config.default_from = ENV.fetch('CONTACT_EMAIL', "mes-demarches#{64.chr}modernisation.gov.pf")
  config.api_version = 'v3.1'
end
