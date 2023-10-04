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
    init_controls if valid?
  end

  def process(demarche, dossier)
    super
    process_condition(:process)
  end

  def check(_dossier)
    process_condition(:control)
  end

  private

  def process_condition(method)
    values = champs_to_values(object_field_values(@dossier, @params[:champ], log_empty: false))
    values = [''] if values.blank?
    values.each do |value|
      value = value&.to_s
      if @controls.key?(value)
        controls = @controls[value]
        Rails.logger.info("Executing tasks for #{@params[:champ]} : '#{value}'")
      else
        controls = @controls['par défaut']
        Rails.logger.info("Executing 'par défaut' tasks as #{@params[:champ]} : '#{value}'") if controls.present?
      end
      raise "No task for value '#{value}'" if controls.nil?

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
      Object.const_get(description.camelize).new({}).tap_name("#{index}:#{description}")
    else
      # hash
      description.map { |taskname, params| Object.const_get(taskname.camelize).new(params).tap_name("#{index}:#{taskname}") }
    end
  end
end
