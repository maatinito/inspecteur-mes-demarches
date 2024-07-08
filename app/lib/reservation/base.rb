# frozen_string_literal: true

module Reservation
  UserRequest = Struct.new(:dossier, :user, :session_name, :date)

  class Base < FieldChecker
    def version
      super + 1
    end

    def required_fields
      super + %i[message_indisponible]
    end

    def authorized_fields
      super + %i[message_disponibilites]
    end

    def process(demarche, dossier)
      @dossier = dossier
      @demarche = demarche

      case @dossier.state
      when 'en_construction'
        book
      when 'refuse', 'sans_suite'
        remove_booking
      end
    end

    private

    def remove_booking
      user_requests(@dossier).each do |user_request|
        Booking.find_by(dossier: user_request.dossier, user: user_request.user)&.destroy
      end
    end

    def book
      user_requests(@dossier).each do |user_request|
        next if already_booked(user_request)

        session = find_or_create_session(user_request.session_name, user_request.date)
        if session_available(session)
          add_booking(session, user_request)
        elsif @params[:message_disponibilites]
          propose_alternatives(user_request)
        else
          send_not_available
        end
      end
    end

    def session_available(session)
      session.present? && session.capacity - session.bookings.size - 1 >= 0
    end

    def already_booked(user_request)
      existing_booking = Booking.find_by(dossier: user_request.dossier, user: user_request.user)
      existing_booking.present? && existing_booking.session.date == user_request.date
    end

    def propose_alternatives(user_request)
      available_sessions = find_available_sessions(user_request.session_name, user_request.date)
      if available_sessions.present?
        send_proposal_message(available_sessions)
      else
        send_not_available
      end
    end

    def add_booking(session, user_request)
      Booking.find_or_create_by(dossier: user_request.dossier, user: user_request.user) do |booking|
        booking.session = session
      end
      DossierPasserEnInstruction.new({}).process(@demarche, @dossier)
    end

    def find_or_create_session(_name, _date)
      # Session.find_or_create_by!(name:, date:, capacity: 1000000)
      raise NotImplementedError 'Must be provided by subclass'
    end

    def user_requests(_dossier)
      raise NotImplementedError 'Must be provided by subclass'
    end

    def find_available_sessions(_name, _date)
      raise NotImplementedError 'Must be provided by subclass'
    end

    def send_not_available
      SendMessage.send(@dossier, instructeur_id_for(@demarche, @dossier), @params[:message_indisponible], check_not_sent: true)
    end

    def send_proposal_message(available_sessions)
      dates = available_sessions.map do |session|
        date = session.date
        displayed_date = date.strftime(date.hour.zero? ? '%d/%m' : '%d/%m à %H:%M')
        "#{displayed_date} (#{session.capacity - session.bookings.size} restants)"
      end.join(', ')
      message = instanciate(@params[:message_disponibilites], { dates: })
      SendMessage.send(@dossier, instructeur_id_for(@demarche, @dossier), message, check_not_sent: true)
    end
  end
end
