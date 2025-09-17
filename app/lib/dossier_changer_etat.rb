# frozen_string_literal: true

class DossierChangerEtat < FieldChecker
  attr_reader :dossier

  def initialize(params)
    super
    @conditions = @params[:conditions]
  end

  def process(demarche, dossier)
    super
    change_state(demarche, dossier) if conditions_ok?(demarche, dossier)
  end

  private

  def change_state(demarche, dossier) end

  def conditions_ok?(_demarche, _dossier)
    true
  end

  def authorized_fields
    super + %i[conditions]
  end

  def passer_en_instruction(demarche, dossier)
    DossierPasserEnInstruction.new({}).process(demarche, dossier)
  end

  def repasser_en_instruction(demarche, dossier)
    DossierRepasserEnInstruction.new({}).process(demarche, dossier)
  end
end
