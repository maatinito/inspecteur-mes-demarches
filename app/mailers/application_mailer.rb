# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: CONTACT_EMAIL
  layout 'mailer'
end
