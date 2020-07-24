# frozen_string_literal: true

# Deseti checks & actions
module Deseti
  # Instruction DESETI
  #   Mes-Demarches refuse automaticalluy mini-deseti
  #      if DESETI was refused, dismissed, or is open
  #   Mes-Demarches dismiss the mini deseti if user has resumed his activity
  #   Mes-Demarches put dossier under instruction if mini-deseti is correct & user has no activity
  class Instruction < InspectorTask
    def initialize(params)
      super

      @passer_en_instruction = DossierPasserEnInstruction.new(params)

      motivation = @params[:motivation_reprise] || MOTIVATION_REPRISE
      @classer_sans_suite = DossierClasserSansSuite.new(params.merge(motivation: motivation))

      @operation = {
        en_construction: refuse_open(params),
        en_instruction: refuse_open(params),
        refuse: refuse_closed(params),
        sans_suite: refuse_dismissed(params)
      }
    end

    def authorized_fields
      super + %i[motivation_reprise motivation_deseti_css motivation_deseti_refuse motivation_deseti_en_instruction]
    end

    def process(demarche, dossier_number)
      dossier = pull_dossier(dossier_number)
      deseti_number = field(dossier, DESETI_FIELD)&.string_value
      instruction(demarche, deseti_number, dossier, dossier_number) if deseti_number.present?
    end

    private

    def instruction(demarche, deseti_number, dossier, dossier_number)
      deseti = pull_deseti(deseti_number.to_i)
      operation = @operation[deseti&.state&.to_sym]
      if operation
        close_dossier(demarche, dossier_number, operation)
      else
        instruction_on_activity(demarche, dossier, dossier_number)
      end
    end

    def instruction_on_activity(demarche, dossier, dossier_number)
      resumed = field(dossier, RESUMED_ACTIVITY_FIELD)&.value
      if resumed
        close_dossier(demarche, dossier_number, @classer_sans_suite)
      else # dossier ready for CPS
        @passer_en_instruction.process(demarche, dossier_number)
      end
    end

    def refuse_open(params)
      motivation = @params[:motivation_en_instruction] || MOTIVATION_DESETI_INSTRUCTION
      DossierRefuser.new(params.merge(motivation: motivation))
    end

    def refuse_closed(params)
      motivation = @params[:motivation_refuse] || MOTIVATION_DESETI_REFUSE
      DossierRefuser.new(params.merge(motivation: motivation))
    end

    def refuse_dismissed(params)
      motivation = @params[:motivation_css] || MOTIVATION_DESETI_CSS
      DossierRefuser.new(params.merge(motivation: motivation))
    end

    def close_dossier(demarche, dossier_number, operation)
      @passer_en_instruction.process(demarche, dossier_number)
      operation.process(demarche, dossier_number)
    end

    def pull_deseti(deseti_number)
      get_dossier(deseti_number, DossierChangerEtat::DossierQuery::Dossier)
    end

    def pull_dossier(dossier_number)
      get_dossier(dossier_number, MesDemarches::Queries::Dossier)
    end

    RESUMED_ACTIVITY_FIELD = "Reprise d'activité"
    DESETI_FIELD = 'Numéro dossier DESETI'

    MOTIVATION_REPRISE = "Reprise d'activité"
    MOTIVATION_DESETI_INSTRUCTION = 'Votre dossier DESETI est toujours en instruction'
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
end
