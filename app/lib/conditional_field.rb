# frozen_string_literal: true

class ConditionalField < FieldChecker
  def version
    super + @controls.values.flatten.map(&:version).reduce(&:+) + 2
  end

  def required_fields
    super + %i[champ valeurs]
  end

  def initialize(params)
    super
    init_controls
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
    if values.blank?
      run_controls(@controls['non renseigné'], method)
    else
      values.each do |value|
        controls = @controls[value]
        controls = @controls['par défaut'] if controls.nil?
        throw "No task for value '#{field&.value}'" if controls.nil?
        run_controls(controls, method)
      end
    end
  end

  def run_controls(controls, method)
    return if controls.blank?

    controls.each do |task|
      case method
      when :control
        task.control(@dossier)
        @messages.push(*task.messages)
      when :process
        task.process(@demarche, @dossier)
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
