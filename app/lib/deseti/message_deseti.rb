class MessageDeseti < FieldChecker

  def initialize(params)
    super
    @jours_ecoules = params['jours_ecoules']
    @message = [*params['corps']].join
  end

  def check(dossier)
    if dossier.state == 'accepte' && dossier.datePassageEnConstruction + @jours_ecoules.days > Time.zone.now
      add_message('dossier', dossier.number, @message)
    end
  end

  def required_fields
    super + %i[corps jours_ecoules]
  end
end
