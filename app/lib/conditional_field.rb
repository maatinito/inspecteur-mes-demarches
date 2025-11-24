# frozen_string_literal: true

class ConditionalField < FieldChecker
  def version
    super + @controls.values.flatten.map(&:version).reduce(0, &:+) + 2
  end

  def required_fields
    super + %i[champ valeurs]
  end

  def initialize(params)
    super
    etat_du_dossier = @params[:etat_du_dossier].presence || %w[en_construction en_instruction accepte sans_suite refuse]
    etat_du_dossier = etat_du_dossier.split(/\s*,\s*/) if etat_du_dossier.is_a?(String)
    @states = Set.new(etat_du_dossier)
    init_controls if valid?
  end

  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    process_condition(:process)
  end

  def check(_dossier)
    process_condition(:control)
  end

  def process_row(row, fields)
    @fields = fields
    @dossier = row
    process_condition(:calcul)
  end

  private

  def process_condition(method)
    values = champs_to_values(object_field_values(@dossier, @params[:champ], log_empty: false))
    values = [''] if values.blank?
    values.each do |value|
      value = value&.to_s
      normalized_value = normalize_boolean_value(value)
      if @controls.key?(normalized_value)
        controls = @controls[normalized_value]
        Rails.logger.info("Executing tasks for #{@params[:champ]} : '#{normalized_value}'")
      else
        controls = @controls['par défaut']
        Rails.logger.info("Executing 'par défaut' tasks as #{@params[:champ]} : '#{normalized_value}'") if controls.present?
      end
      raise "No task for value '#{normalized_value}'" if controls.nil?

      run_controls(controls, method)
    end
  end

  def run_controls(controls, method)
    return if controls.blank?

    controls.each do |task|
      Rails.logger.info("Applying task #{task.class.name}")
      Rails.logger.tagged(task.name) do
        case method
        when :control
          task.control(@dossier)
          @messages.push(*task.messages)
        when :process
          task.process(@demarche, @dossier)
        when :calcul
          task.process_row(@dossier, @fields)
        end
        @updated_dossiers += task.updated_dossiers
        @dossiers_to_recheck += task.dossiers_to_recheck
        @dossier = DossierActions.on_dossier(@dossier.number) if task.dossier_updated?(@dossier)
      end
    end
  end

  def init_controls
    @controls = @params[:valeurs].transform_values do |config|
      next [] if config.blank? || !config.is_a?(Array)

      controls = config.map.with_index do |description, i|
        create_control(description, i)
      end.flatten
      controls.reject(&:valid?).each { |task| Rails.logger.error("#{task.class.name}: #{task.errors.join(',')}") }
      controls.filter(&:valid?)
    end
  end

  def create_control(description, index)
    if description.is_a?(String)
      Rails.logger.warn("Création de la tache #{description.camelize}")
      Object.const_get(description.camelize).new({}).tap_name("#{index}:#{description}")
    else
      # hash
      description.map do |taskname, params|
        Rails.logger.warn("Création de la tache #{taskname.camelize} avec #{params}")
        Object.const_get(taskname.camelize).new(params).tap_name("#{index}:#{taskname}")
      end
    end
  end

  def normalize_boolean_value(value)
    case value
    when 'true'
      'Oui'
    when 'false'
      'Non'
    else
      value
    end
  end
end
