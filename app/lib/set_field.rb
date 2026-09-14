# frozen_string_literal: true

class SetField < FieldChecker
  # Sans etat_du_dossier déclaré, la tâche agit sur tous les états (comme
  # conditional_field) : imbriquée dans un when_ok ou un conditional_field, elle
  # n'hérite pas du périmètre parent et le défaut « en_construction » des
  # FieldChecker la ferait cesser d'agir sur les dossiers en instruction.
  TOUS_LES_ETATS = %w[en_construction en_instruction accepte sans_suite refuse].freeze

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
    @states = Set.new(TOUS_LES_ETATS) if @params[:etat_du_dossier].blank?
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
    return unless must_check?(dossier)

    field = @params[:champ]
    value = @params[:valeur]
    value = instanciate(value) if value.is_a?(String)
    target_annotation = annotation(field, warn_if_empty: false)
    if target_annotation.nil?
      Rails.logger.error("Sur le dossier #{dossier.number}, l'annotation '#{field}' n'existe pas : set_field ignoré.")
      return
    end

    value = cast_to_annotation_type(target_annotation, value) if value.is_a?(String)
    value = decalage(target_annotation, value) if @shift

    # Vérifier si on doit modifier uniquement si le champ est vide
    return if si_vide? && champ_value(target_annotation).present?

    return unless SetAnnotationValue.set_value(@dossier, @demarche.instructeur, field, value)

    dossier_updated(@dossier)
  end

  F2E = { jours: :days, mois: :months, annees: :years, heures: :hours, minutes: :minutes, semaines: :weeks }.freeze

  def cast_to_annotation_type(target, value)
    case target.__typename
    when 'DateChamp'
      Date.parse(value)
    when 'DatetimeChamp'
      Time.zone.parse(value)
    when 'IntegerNumberChamp'
      value.to_i
    else
      value
    end
  rescue ArgumentError
    value
  end

  def decalage(annotation, value)
    date = case annotation.__typename
           when 'DateChamp'
             value.is_a?(Date) ? value : Date.parse(value)
           when 'DatetimeChamp'
             value.is_a?(Time) ? value : Time.zone.parse(value)
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
