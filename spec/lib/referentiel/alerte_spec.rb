# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Referentiel::Alerte do
  include ActiveSupport::Testing::TimeHelpers

  let(:table) { ReferentielTable.create!(backend: 'baserow', table_ref: '42', mode: 'dlnuf', proprietaire: 7, refus_depuis: 1.hour.ago) }
  let(:refus) { Referentiel::Verrou::Refus.new('Table refusée.', table) }

  around do |example|
    adaptateur = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = adaptateur
  end

  before { allow(Sentry).to receive(:capture_message) }

  it 'envoie un courriel au premier appel' do
    expect { expect(described_class.signaler(refus)).to be(true) }
      .to have_enqueued_mail(NotificationMailer, :report_error)
    expect(table.reload.alerte_le).to be_within(5.seconds).of(Time.zone.now)
    expect(Sentry).to have_received(:capture_message).with(/Synchronisation et effacement suspendus/)
    expect(Sentry).to have_received(:capture_message).with(/rejoués automatiquement/)
  end

  it 'n envoie rien au second appel dans les 24 h' do
    described_class.signaler(refus)
    expect { expect(described_class.signaler(refus)).to be(false) }
      .not_to have_enqueued_mail(NotificationMailer, :report_error)
  end

  it 'envoie un nouveau courriel après 25 h' do
    described_class.signaler(refus)
    travel 25.hours do
      expect { expect(described_class.signaler(refus)).to be(true) }
        .to have_enqueued_mail(NotificationMailer, :report_error)
    end
  end

  it 'ne plante pas sans table' do
    expect(described_class.signaler(Referentiel::Verrou::Refus.new('x'))).to be(false)
  end

  it 'informer envoie un courriel sans limite de fréquence' do
    expect { 2.times { described_class.informer(table, 'info') } }
      .to have_enqueued_mail(NotificationMailer, :report_error).twice
  end
end
