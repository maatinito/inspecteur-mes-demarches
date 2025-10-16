# frozen_string_literal: true

class Schedule < FieldChecker
  def version
    super + @controls.map(&:version).reduce(0, &:+) + 2
  end

  def required_fields
    super + %i[champ_date_de_reference champ_stockage taches]
  end

  def authorized_fields
    super + %i[decalage_jours decalage_heures heure champ_stockage delai_max_heures identifiant]
  end

  def initialize(params)
    super
    return unless valid?

    init_controls
  end

  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    when_time = run_at
    if Time.zone.now > when_time
      hours_delay = @params[:delai_max_heures]
      if hours_delay.present? && Time.zone.now < when_time + hours_delay.hours
        if annotation(@params[:champ_stockage], warn_if_empty: false)&.value == when_time.to_s
          Rails.logger.info("Tache programmée à #{when_time} non exécutée car déjà effectuée.")
        else
          run_controls(@controls, :process)
          SetAnnotationValue.set_value(@dossier, @demarche.instructeur, @params[:champ_stockage], when_time.to_s)
          dossier_updated(dossier)
        end
      else
        Rails.logger.info("Tache programmée à #{when_time} non exécutée car trop en retard.")
      end
    else
      ScheduledTask.clear(dossier: @dossier.number, task: task_identifier)
      ScheduledTask.enqueue(@dossier.number, task_identifier, @params, when_time)
    end
  end

  private

  def task_identifier
    @params[:identifiant].present? ? "#{self.class.name.underscore}/#{@params[:identifiant]}" : self.class
  end

  def run_at
    date = datetime_pivot
    return unless date

    date = Time.zone.parse(date)
    date += @params[:decalage_jours].days if @params.key?(:decalage_jours)
    date += @params[:decalage_heures].hours if @params.key?(:decalage_heures)
    if @params.key?(:heure)
      match = @params[:heure].match(/(\d{1,2})[h:](\d{2})/)
      date = date.change(hour: match[1].to_i, min: match[2].to_i)
    end
    date
  end

  def datetime_pivot
    date = field(@params[:champ_date_de_reference])
    unless date.present? && %w[DateTimeChamp DateChamp].include?(date.__typename) && date.value.present?
      Rails.logger.info("L'attribut #{@params[:champ]} ne donne aucune date #{date} ==> aucune tache ne sera exécutée")
      return
    end
    date.value
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
    @controls = @params[:taches].map.with_index do |description, i|
      create_control(description, i)
    end.flatten
    @controls.reject(&:valid?).each { |task| Rails.logger.error("#{task.class.name}: #{task.errors.join(',')}") }
    @controls.filter!(&:valid?)
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
