# frozen_string_literal: true

module Reservation
  class Jentreprends < Base
    SESSION_NAME = 'Jentreprends'

    def required_fields
      super + %i[champ_date capacite]
    end

    private

    def user_requests(dossier)
      date = DateTime.parse(param_field(:champ_date)&.value)
      [UserRequest.new(dossier.number, 'user', SESSION_NAME, date)]
    end

    def find_or_create_session(name, date)
      return nil if date.wday != 5 || date < Date.today

      Session.find_or_create_by(name:, date:) do |session|
        session.update(capacity: @params[:capacite])
      end
    end

    def find_available_sessions(_name, _date)
      date = Time.zone.now.change(hour: 0, min: 0, sec: 0)
      days_until_next_friday = (12 - date.wday) % 7
      days_until_next_friday = 7 if days_until_next_friday.zero?
      date += days_until_next_friday.days

      end_date = 2.months.since
      sessions = []

      while sessions.size < 2 && date <= end_date
        session = find_or_create_session(SESSION_NAME, date)
        sessions << session if session&.bookings&.size&.< session&.capacity # rubocop:disable Style/SafeNavigationChainLength
        date += 7.days
      end

      sessions
    end
  end
end
