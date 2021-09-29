# frozen_string_literal: true

class ConditionalField < FieldChecker
  def version
    super + @controls.values.flatten.reduce(2) { |s, c| s + c.version } + 1
  end

  def required_fields
    super + %i[champ valeurs]
  end

  def initialize(params)
    super
    init_controls
  end

  def check(dossier)
    field = param_field(:champ)
    controls = @controls[field&.value]
    throw "No list for value '#{field&.value}'" unless controls.is_a? Array
    controls.each do |task|
      task.control(dossier)
      @messages.push(*task.messages)
    end
  end

  private

  def init_controls
    @controls = @params[:valeurs].transform_values do |config|
      controls = config.map.with_index do |description, i|
        create_control(description, i)
      end.flatten
      controls.reject(&:valid?).each { |task| puts "#{task.class.name}: #{task.errors.join(',')}" }
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
