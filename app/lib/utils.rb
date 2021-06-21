# frozen_string_literal: true

module Utils
  def dossier_field_value(dossier, field, warn_if_empty: true)
    return nil if dossier.nil? || field.blank?

    objects = [*dossier]
    field.split(/\./).each do |name|
      objects = objects.flat_map { |object| object.champs.select { |champ| champ.label == name } }
      if warn_if_empty && objects.blank?
        Rails.logger.warn("Sur le dossier #{dossier.number}, le champ #{field} est vide.")
      end
    end
    objects&.first
  end

  MONTHS = %w[zero janvier février mars avril mai juin juillet août septembre octobre novembre décembre].freeze

  def report_index(dossier, month)
    # DIESE initial
    start_month = dossier_field_value(dossier, 'Mois 1', warn_if_empty: false)&.value&.downcase
    start_month = dossier_field_value(dossier, 'Mois M', warn_if_empty: false)&.value&.downcase if start_month.nil?
    if start_month.nil?
      # CSE initial
      start_month = dossier_field_value(dossier, 'Date de démarrage de la mesure (Mois 1)', warn_if_empty: false)&.value
      start_month = Date.parse(start_month).month if start_month.present?
    end
    if start_month.nil?
      # Avenant
      mois_2 = dossier_field_value(dossier, 'Nombre de salariés DiESE au mois 2', warn_if_empty: false)
      if mois_2.present?
        start_month = mois_2.value.blank? ? 11 : 12
      end
    end
    if start_month.nil?
      throw "Le dossier initial #{dossier.number} n'a pas de champ permettant de connaitre le mois de démarrage de la mesure. (champ mois_1?)"
    end

    start_month = MONTHS.index(start_month) if start_month.is_a?(String)
    current_month = MONTHS.index(month.downcase)
    throw "Impossible de reconnaitre les mois de démarrage (#{start_month})" if start_month.nil?

    throw "Impossible de reconnaitre les mois de l'etat en cours (#{month})" if current_month.nil?

    current_month += 12 if current_month < start_month
    current_month - start_month + 1
  end

  def symbolize(name)
    name.tr('%', 'P').parameterize.underscore.to_sym
  end

  def create_target_dir(dossier)
    nb = dossier.number.to_s
    nb = '0' * (6 - nb.length) + nb if nb.length < 6
    dir = "#{output_dir}/#{nb}"
    FileUtils.mkpath(dir)
    dir
  end

  def initial_dossier
    if @initial_dossier.nil?
      initial_dossier_field = param_value(:champ_dossier)
      if initial_dossier_field.nil?
        throw "Impossible de trouver le dossier prévisionnel via le champ #{params[:champ_dossier]}"
      end

      @initial_dossier = initial_dossier_field.dossier
      if @initial_dossier.nil?
        throw "Mes-Démarche n'a pas retourné le sous-dossier #{initial_dossier_field.string_value} à partir du dossier #{dossier.number}"
      end
    end
    @initial_dossier
  end
end
