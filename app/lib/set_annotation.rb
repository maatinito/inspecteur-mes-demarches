# frozen_string_literal: true

class SetAnnotation < FieldChecker
  def required_fields
    super + %i[annotation valeur]
  end

  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    already_set = param_annotation(:annotation, warn_if_empty: false)&.value.present?
    if already_set
      Rails.logger.info("#{@params[:annotation]} ignored as it already contains value")
    else
      Rails.logger.info("Setting #{@params[:annotation]} to #{@params[:valeur]}")
      modified = SetAnnotationValue.set_value(dossier, demarche.instructeur, params[:annotation], instanciate(@params[:valeur]))
      dossier_updated(dossier) if modified
    end
  end
end
