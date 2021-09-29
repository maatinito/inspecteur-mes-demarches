# frozen_string_literal: true

module Deseti
  class MessageDeseti < FieldChecker
    def initialize(params)
      super
      @jours_ecoules = @params[:jours_ecoules]
      @message = [*@params[:corps]].join
    end

    def check(dossier)
      add_message('dossier', dossier.number, @message) if dossier.state == 'accepte' && dossier.datePassageEnConstruction + @jours_ecoules.days > Time.zone.now
    end

    def required_fields
      super + %i[corps jours_ecoules]
    end
  end
end
