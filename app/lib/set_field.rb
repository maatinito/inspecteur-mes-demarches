# frozen_string_literal: true

class SetField < FieldChecker
  def version
    super + 2
  end

  def required_fields
    %i[champ valeur]
  end

  def authorized_fields
    super + %i[decalage si_vide]
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

    # Vérifier si on doit modifier uniquement si le champ est vide
    if si_vide?
      current_annotation = annotation(field, warn_if_empty: false)
      current_value = current_annotation ? champ_value(current_annotation) : nil
      return if current_value.present?
    end

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

  private

  def si_vide?
    param = @params[:si_vide]
    return false if param.nil?

    case param
    when TrueClass, FalseClass
      param
    when String
      %w[true oui yes vrai t o y v 1].include?(param.downcase)
    else
      false
    end
  end
end
