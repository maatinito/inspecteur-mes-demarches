# frozen_string_literal: true

module Daf
  class Message < FieldChecker
    def version
      super + 1
    end

    def required_fields
      super + %i[message]
    end

    def authorized_fields
      super + %i[champ_telephone sms]
    end

    include Payzen::StringTemplate

    def process(demarche, dossier)
      super

      SendMessage.send(dossier, instructeur_id, instanciate(@params[:message]), check_not_sent: true)
    end
  end
end
