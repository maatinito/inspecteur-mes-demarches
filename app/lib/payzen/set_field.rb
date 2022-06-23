# frozen_string_literal: true

module Payzen
  class SetField < Task
    include StringTemplate

    def version
      super + 1
    end

    def required_fields
      %i[champ valeur]
    end

    def handle_order(_order)
      field = @params[:champ]
      template = @params[:valeur]
      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, field, instanciate(template, source))
    end
  end
end
