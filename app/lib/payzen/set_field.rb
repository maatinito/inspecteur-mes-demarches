# frozen_string_literal: true

module Payzen
  class SetField < Task
    include Payzen::StringTemplate

    def version
      super + 1
    end

    def required_fields
      %i[champ valeur]
    end

    def handle_order(order)
      field = @params[:champ]
      template = @params[:valeur]
      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, field, instanciate(template, order))
    end
  end
end
