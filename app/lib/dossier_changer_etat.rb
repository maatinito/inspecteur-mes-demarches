# frozen_string_literal: true

class DossierChangerEtat < InspectorTask
  def process(demarche, dossier_number)
    @dossier = nil
    @dossier_number = dossier_number
    change_state(demarche, dossier) if conditions_ok(demarche, dossier)
  end

  private

  DossierQuery = MesDemarches::Client.parse <<-'GRAPHQL'
    query Dossier($dossier: Int!) {
      dossier(number: $dossier) {
          id
          state
          datePassageEnConstruction
          datePassageEnInstruction
          dateTraitement
          dateDerniereModification
      }
    }
  GRAPHQL

  def dossier
    @dossier ||= get_dossier(@dossier_number)
  end

  def get_dossier(dossier_number)
    response = MesDemarches::Client.query(dossier_query, variables: { dossier: dossier_number })
    data = response.data
    data&.dossier
  end

  def dossier_query
    DossierQuery::Dossier
  end

  def change_state(demarche, dossier) end

  def conditions_ok(_demarche, _dossier)
    true
  end

  def authorized_fields
    super + %i[conditions]
  end

  def required_fields
    super
  end

  def initialize(params)
    super
    @conditions = @params[:conditions]
  end
end
