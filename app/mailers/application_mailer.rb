# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: ENV['CONTACT_EMAIL']
  layout 'mailer'
end
