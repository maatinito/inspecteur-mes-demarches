# frozen_string_literal: true

module Utils
  def symbolize(name)
    name.tr('%', 'P').parameterize.underscore.to_sym
  end

  def create_target_dir(dossier)
    nb = dossier.number.to_s
    nb = ('0' * (6 - nb.length)) + nb if nb.length < 6
    dir = "#{output_dir}/#{nb}"
    FileUtils.mkpath(dir)
    dir
  end

  def initial_dossier
    if @initial_dossier.nil?
      initial_dossier_field = param_field(:champ_dossier)
      throw "Impossible de trouver le dossier prévisionnel via le champ #{params[:champ_dossier]}" if initial_dossier_field.nil?

      @initial_dossier = initial_dossier_field.dossier
      throw "Mes-Démarche n'a pas retourné le sous-dossier #{initial_dossier_field.string_value} à partir du dossier #{dossier.number}" if @initial_dossier.nil?
    end
    @initial_dossier
  end
end
