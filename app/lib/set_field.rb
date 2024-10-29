# frozen_string_literal: true

class SetField < FieldChecker
  def version
    super + 1
  end

  def required_fields
    %i[champ valeur]
  end

  def process(demarche, dossier)
    super
    field = @params[:champ]
    value = @params[:valeur]
    value = instanciate(value) if value.is_a?(String)
    return unless SetAnnotationValue.set_value(@dossier, @demarche.instructeur, field, value)

    dossier_updated(@dossier)
  end
end
