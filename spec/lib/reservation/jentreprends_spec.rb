# frozen_string_literal: true

require 'rails_helper'
require File.expand_path('../../../app/lib/dossier_actions', __dir__)

RSpec.describe 'Reservation::Jentreprends' do
  include ActiveSupport::Testing::TimeHelpers

  let(:dossier_nb1) { 426_838 }
  let(:dossier1) { DossierActions.on_dossier(dossier_nb1) }
  let(:dossier_nb2) { 426_839 }
  let(:dossier2) { DossierActions.on_dossier(dossier_nb2) }
  let(:demarche) { double(Demarche) }
  let(:instructeur) { 'instructeur' }

  before do
    allow(demarche).to receive(:instructeur).and_return(instructeur)
    allow(SendMessage).to receive(:send)
    allow(controle).to receive(:instructeur_id_for).and_return(instructeur)
  end

  subject do
    controle.process(demarche, dossier)
    controle
  end

  context 'valid control' do
    let(:controle) { FactoryBot.build :reservation_jentreprends }
    it 'should be valid' do
      expect(controle.valid?).to be_truthy
    end
  end

  context 'session free,' do
    before do
      expect_any_instance_of(DossierPasserEnInstruction).to receive(:process)
    end

    let(:controle) { FactoryBot.build :reservation_jentreprends }
    let(:dossier) { dossier1 }
    it 'books correctly', vcr: { cassette_name: 'booking-1' } do
      travel_to Time.new(2024, 7, 23, 12, 0, 0) do
        subject

        expect(Session.count).to eq(1)
        expect(Booking.count).to eq(1)
        booking = Booking.first
        expect(booking.dossier).to eq(dossier.number)
        expect(booking.session).to eq(Session.first)
      end
    end
  end

  context 'session full,' do
    let(:controle) { FactoryBot.build :reservation_jentreprends }
    let(:dossier) { dossier1 }
    let(:session) { create :session }
    let(:booking) { create :booking, session: }

    before do
      expect(SendMessage).to receive(:send).with(dossier, instructeur, message, check_not_sent: true)
    end

    context 'without availabity message' do
      let(:message) { 'indisponible' }
      it 'cannot book and propose alternative dates', vcr: { cassette_name: 'booking-1' } do
        booking
        subject
      end
    end
    context 'with availabity message' do
      let(:controle) { FactoryBot.build :reservation_jentreprends, :with_disponibilites }
      let(:unavailable_session) { FactoryBot.create :session, capacity: 0, date: Time.zone.parse('2024-08-09') }
      let(:message) { "disponibilites * 02/08 (1 restants)\n* 16/08 (1 restants)\n" }
      it 'cannot book and propose alternative dates', vcr: { cassette_name: 'booking-1' } do
        travel_to Time.zone.local(2024, 8, 1, 12, 12, 0) do
          booking
          unavailable_session
          subject
        end
      end
    end
  end
end
