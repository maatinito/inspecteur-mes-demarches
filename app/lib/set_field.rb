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
    template = @params[:valeur]
    return unless SetAnnotationValue.set_value(@dossier, @demarche.instructeur, field, instanciate(template))

    dossier_updated(@dossier)
  end
end
