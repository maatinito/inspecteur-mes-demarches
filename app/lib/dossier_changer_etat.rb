# frozen_string_literal: true

class DossierChangerEtat < FieldChecker
  attr_reader :dossier

  def initialize(params)
    super
    @conditions = @params[:conditions]
  end

  def process(demarche, dossier)
    super
    change_state(demarche, dossier) if conditions_ok(demarche, dossier)
  end

  private

  def change_state(demarche, dossier) end

  def conditions_ok(_demarche, _dossier)
    true
  end

  def authorized_fields
    super + %i[conditions]
  end

  protected

  def instructeur_id(demarche, dossier)
    first_instructeur(dossier) || demarche.instructeur
  end

  def first_instructeur(dossier)
    d = MesDemarches::Client.query(Queries::Instructeurs, variables: { number: dossier.number })
    throw StandardError.new d.errors if d.errors.present?

    d.data.dossier.instructeurs.first&.id
  end

  Queries = MesDemarches::Client.parse <<-'GRAPHQL'
    query Instructeurs($number: Int!) {
      dossier(number: $number) {
        instructeurs {
          id
        }
      }
    }
  GRAPHQL
end
