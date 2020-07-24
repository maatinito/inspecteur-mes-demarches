# frozen_string_literal: true

class Deseti::Instruction < InspectorTask
  def initialize(params)
    super

    @passer_en_instruction = DossierPasserEnInstruction.new(params)

    motivation = @params[:motivation_reprise] || MOTIVATION_REPRISE
    @classer_sans_suite = DossierClasserSansSuite.new(params.merge(motivation: motivation))

    motivation = @params[:motivation_en_instruction] || MOTIVATION_DESETI_EN_INSTRUCTION
    refuser_deseti_open = DossierRefuser.new(params.merge(motivation: motivation))

    motivation = @params[:motivation_refuse] || MOTIVATION_DESETI_REFUSE
    refuser_deseti_closed = DossierRefuser.new(params.merge(motivation: motivation))

    motivation = @params[:motivation_css] || MOTIVATION_DESETI_CSS
    refuser_deseti_dismissed = DossierRefuser.new(params.merge(motivation: motivation))

    @operation = {
      en_construction: refuser_deseti_open,
      en_instruction: refuser_deseti_open,
      refuse: refuser_deseti_closed,
      sans_suite: refuser_deseti_dismissed
    }
  end

  def process(demarche, dossier_number)
    dossier = pull_dossier(dossier_number)
    deseti_number = field(dossier, DESETI_FIELD)&.string_value
    if deseti_number.present?
      deseti = pull_deseti(deseti_number.to_i)
      operation = @operation[deseti&.state&.to_sym]
      if operation
        close_dossier(demarche, dossier_number, operation)
      else
        resumed = field(dossier, RESUMED_ACTIVITY_FIELD)&.value
        if resumed
          close_dossier(demarche, dossier_number, @classer_sans_suite)
        else # dossier ready for CPS
          @passer_en_instruction.process(demarche, dossier_number)
        end
      end
    end
  end

  private

  public def authorized_fields
    super + %i[motivation_reprise motivation_deseti_css motivation_deseti_refuse motivation_deseti_en_instruction]
  end

  def close_dossier(demarche, dossier_number, operation)
    @passer_en_instruction.process(demarche, dossier_number)
    operation.process(demarche, dossier_number)
  end

  def pull_deseti(deseti_number)
    deseti = get_dossier(deseti_number, DossierChangerEtat::DossierQuery::Dossier)
  end

  def pull_dossier(dossier_number)
    dossier = get_dossier(dossier_number, MesDemarches::Queries::Dossier)
  end

  RESUMED_ACTIVITY_FIELD = "Reprise d'activité"
  DESETI_FIELD = 'Numéro dossier DESETI'

  MOTIVATION_REPRISE = "Reprise d'activité"
  MOTIVATION_DESETI_EN_INSTRUCTION = 'Votre dossier DESETI est toujours en instruction'
  MOTIVATION_DESETI_REFUSE = 'Votre dossier DESETI a été rejeté'
  MOTIVATION_DESETI_CSS = 'Votre dossier DESETI a été classé sans suite'

  def fields(dossier, field)
    @accessed_fields.add(field)
    objects = [*dossier]
    field.split(/\./).each do |name|
      objects = objects.flat_map { |object| object.champs.select { |champ| champ.label == name } }
    end
    objects
  end

  def field(dossier, field)
    value = fields(dossier, field)
    value = value[0] if value.is_a? Array
    value
  end

  def get_dossier(dossier_number, query)
    response = MesDemarches::Client.query(query, variables: { dossier: dossier_number })
    data = response.data
    data&.dossier
  end
end
