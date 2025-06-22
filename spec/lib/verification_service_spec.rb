# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VerificationService do
  let(:service) { VerificationService.new }

  before do
    VerificationService.clear_network_error_notifications
  end

  describe '#network_error?' do
    it 'detects network errors' do
      network_errors = [
        StandardError.new('Connection refused'),
        StandardError.new('Network timeout'),
        StandardError.new('Host not found'),
        StandardError.new('Connection timeout'),
        StandardError.new('Socket error')
      ]

      network_errors.each do |error|
        expect(service.network_error?(error)).to be true
      end
    end

    it 'does not detect non-network errors' do
      non_network_errors = [
        StandardError.new('Invalid data format'),
        StandardError.new('Missing field'),
        StandardError.new('Validation failed')
      ]

      non_network_errors.each do |error|
        expect(service.network_error?(error)).to be false
      end
    end
  end

  describe '#should_notify_error?' do
    let(:network_exception) { StandardError.new('Connection refused') }
    let(:non_network_exception) { StandardError.new('Invalid data') }

    it 'always allows notification for non-network errors' do
      expect(service.should_notify_error?('Test error', non_network_exception)).to be true
    end

    it 'allows first notification for network errors' do
      expect(service.should_notify_error?('Network error', network_exception)).to be true
    end

    it 'blocks repeated notifications within cooldown period' do
      service.mark_error_notified('Network error', network_exception)
      expect(service.should_notify_error?('Network error', network_exception)).to be false
    end

    it 'allows notification after cooldown period' do
      service.mark_error_notified('Network error', network_exception)

      # Simulate time passage
      allow(Time).to receive(:current).and_return(2.hours.from_now)

      expect(service.should_notify_error?('Network error', network_exception)).to be true
    end
  end

  describe '#report_error' do
    let(:mailer_double) { double('NotificationMailer') }
    let(:network_exception) { StandardError.new('Connection refused') }

    before do
      allow(NotificationMailer).to receive(:with).and_return(mailer_double)
      allow(mailer_double).to receive(:report_error).and_return(mailer_double)
      allow(mailer_double).to receive(:deliver_later)
    end

    it 'sends notification for first network error' do
      service.report_error('Network error', network_exception)

      expect(NotificationMailer).to have_received(:with)
      expect(mailer_double).to have_received(:deliver_later)
    end

    it 'does not send notification for repeated network error within cooldown' do
      service.report_error('Network error', network_exception)
      service.report_error('Network error', network_exception)

      expect(NotificationMailer).to have_received(:with).once
      expect(mailer_double).to have_received(:deliver_later).once
    end
  end
end
