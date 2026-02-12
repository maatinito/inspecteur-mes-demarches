# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VerificationService do
  let(:service) { VerificationService.new }

  describe '.retry_reference_time' do
    it 'returns BOOT_TIME when it is after last 8am' do
      boot_time = VerificationService::BOOT_TIME
      last_8am = Time.current.change(hour: 8)
      last_8am -= 1.day if last_8am > Time.current

      result = VerificationService.retry_reference_time
      expect(result).to eq([boot_time, last_8am].max)
    end

    it 'returns a time that is not in the future' do
      expect(VerificationService.retry_reference_time).to be <= Time.current
    end
  end

  describe '#report_error' do
    let(:mailer_double) { double('NotificationMailer') }
    let(:exception) { StandardError.new('Something went wrong') }

    before do
      allow(NotificationMailer).to receive(:with).and_return(mailer_double)
      allow(mailer_double).to receive(:report_error).and_return(mailer_double)
      allow(mailer_double).to receive(:deliver_later)
    end

    it 'sends notification' do
      service.report_error('Error', exception)

      expect(NotificationMailer).to have_received(:with)
      expect(mailer_double).to have_received(:deliver_later)
    end
  end
end
