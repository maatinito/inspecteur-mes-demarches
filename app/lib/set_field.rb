# frozen_string_literal: true

class SetField < FieldChecker
  def version
    super + 1
  end

  def required_fields
    %i[champ valeur]
  end

  def authorized_fields
    super + %i[decalage]
  end

  def initialize(params)
    super
    shift = @params[:decalage]
    return unless shift.present?

    if shift.is_a?(Hash) && shift.all? { |k, _v| F2E.key?(k.to_sym) }
      @shift = shift.transform_keys { |k| F2E[k.to_sym] }
    else
      @errors << "l'attribut 'decalage' doit contenir uniquement les attributs #{F2E.keys.join(', ')} ."
    end
  end

  def process(demarche, dossier)
    super
    field = @params[:champ]
    value = @params[:valeur]
    value = instanciate(value) if value.is_a?(String)
    value = decalage(annotation(field), value) if @shift

    return unless SetAnnotationValue.set_value(@dossier, @demarche.instructeur, field, value)

    dossier_updated(@dossier)
  end

  F2E = { jours: :days, mois: :months, annees: :years, heures: :hours, minutes: :minutes, semaines: :weeks }.freeze

  def decalage(annotation, value)
    date = case annotation.__typename
           when 'DateChamp'
             Date.parse(value)
           when 'DatetimeChamp'
             Time.zone.parse(value)
           end
    return value unless date.present?

    date.advance(@shift)
  end
end
