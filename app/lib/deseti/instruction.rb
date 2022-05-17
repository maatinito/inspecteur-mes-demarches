# frozen_string_literal: true

# Deseti checks & actions
module Deseti
  # Instruction DESETI
  #   Mes-Demarches refuse automaticalluy mini-deseti
  #      if DESETI was refused, dismissed, or is open
  #   Mes-Demarches dismiss the mini deseti if user has resumed his activity
  #   Mes-Demarches put dossier under instruction if mini-deseti is correct & user has no activity
  class Instruction < InspectorTask
    attr_reader :passer_en_instruction, :classer_sans_suite, :operation

    def initialize(params)
      super

      @passer_en_instruction = DossierPasserEnInstruction.new(params)
      @classer_sans_suite = action(DossierClasserSansSuite, params, motivation(:motivation_reprise))

      @operation = {
        en_construction: action(DossierRefuser, params, motivation(:motivation_deseti_en_construction)),
        en_instruction: action(DossierRefuser, params, motivation(:motivation_deseti_en_instruction)),
        refuse: action(DossierRefuser, params, motivation(:motivation_deseti_refuse)),
        sans_suite: action(DossierClasserSansSuite, params, motivation(:motivation_deseti_sans_suite))
      }

      @champ = @params[:champ] || DESETI_FIELD
      @champ_reprise = @params[:champ_reprise] || RESUMED_ACTIVITY_FIELD
    end

    def authorized_fields
      super + %i[
        champ
        champ_reprise
        motivation_reprise
        motivation_deseti_sans_suite
        motivation_deseti_refuse
        motivation_deseti_en_construction
        motivation_deseti_en_instruction
      ]
    end

    def process(demarche, dossier_number)
      puts "-- dossier #{dossier_number} ok ==> automatic instruction --"
      dossier = pull_dossier(dossier_number)
      deseti_number = dossier_field(dossier, @champ)&.string_value
      throw StandardError.new "Impossible de trouver le champ #{@champ} dans la démarche #{demarche.id}" unless deseti_number
      instruction(demarche, deseti_number, dossier, dossier_number) if deseti_number.present?
    end

    private

    RESUMED_ACTIVITY_FIELD = "Reprise d'activité"
    DESETI_FIELD = 'Numéro dossier DESETI'

    MOTIVATIONS = {
      motivation_deseti_en_instruction: 'Votre précédent dossier DESETI est toujours en instruction',
      motivation_deseti_en_construction: 'Votre précédent dossier DESETI est toujours en instruction',
      motivation_deseti_refuse: 'Votre précédent dossier DESETI a été rejeté',
      motivation_deseti_sans_suite: 'Votre précédent dossier DESETI a été classé sans suite',
      motivation_reprise: 'Vous avez repris votre activité'
    }.freeze

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
      resumed = dossier_field(dossier, @champ_reprise)
      throw StandardError.new "Le champ #{@champ_reprise} n'existe pas sur la démarche #{demarche.id}" unless resumed

      if resumed.value
        close_dossier(demarche, dossier_number, @classer_sans_suite)
      else
        # dossier ready for CPS
        @passer_en_instruction.process(demarche, dossier_number)
      end
    end

    def motivation(name)
      @params[name] || MOTIVATIONS[name]
    end

    def action(klass, params, motivation)
      klass.new(params.merge(motivation:))
    end

    def close_dossier(demarche, dossier_number, operation)
      puts '-- closing dossier --'
      pp operation

      @passer_en_instruction.process(demarche, dossier_number)
      operation.process(demarche, dossier_number)
    end

    def pull_deseti(deseti_number)
      get_dossier(deseti_number, DossierChangerEtat::DossierQuery::Dossier)
    end

    def pull_dossier(dossier_number)
      get_dossier(dossier_number, MesDemarches::Queries::Dossier)
    end

    def fields(dossier, field)
      @accessed_fields.add(field)
      objects = [*dossier]
      field.split(/\./).each do |name|
        objects = objects.flat_map { |object| object.champs.select { |champ| champ.label == name } }
      end
      objects
    end

    def get_dossier(dossier_number, query)
      response = MesDemarches::Client.query(query, variables: { dossier: dossier_number })
      data = response.data
      data&.dossier
    end
  end
end
