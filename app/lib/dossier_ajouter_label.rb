# frozen_string_literal: true

class DossierAjouterLabel < FieldChecker
  def required_fields
    super + %i[label]
  end

  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    label_name = @params[:label]
    return if dossier_has_label?(dossier, label_name)

    label_id = DossierLabel.find_label_id(demarche.id, label_name)
    unless label_id
      Rails.logger.warn("Label '#{label_name}' introuvable sur la démarche #{demarche.id}")
      return
    end

    DossierLabel.add(dossier.id, label_id)
    dossier_updated(dossier)
  end

  private

  def dossier_has_label?(dossier, label_name)
    dossier.respond_to?(:labels) && dossier.labels&.any? { |l| l.name == label_name }
  end
end
