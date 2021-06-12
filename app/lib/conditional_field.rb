# frozen_string_literal: true

class ConditionalField < FieldChecker
  def version
    super + @controls.values.flatten.reduce(2) { |s, c| s + c.version }
  end

  def required_fields
    super + %i[champ valeurs]
  end

  def initialize(params)
    super
    init_controls
  end

  def check(dossier)
    field = param_value(:champ)
    controls = @controls[field&.value]
    if controls.is_a? Array
      controls.each do |task|
        task.control(dossier)
        @messages.push(*task.messages)
      end
    end
    # TODO: erreur si valeur inconnu
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

  def create_control(description, i)
    control = if control.is_a?(String)
                Object.const_get(control.camelize).new({})
              else
                # hash
                description.map { |taskname, params| Object.const_get(taskname.camelize).new(params) }
              end
    control.name = "#{i}:#{taskname}"
    control
  end
end
