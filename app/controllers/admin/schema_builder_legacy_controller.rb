# frozen_string_literal: true

module Admin
  # Page de transition pour les anciennes URLs `/admin/baserow_schema*` et
  # `/admin/grist_schema*`. Liste les démarches accessibles à l'utilisateur
  # connecté et propose un lien vers le nouveau dashboard scopé par démarche.
  class SchemaBuilderLegacyController < ApplicationController
    before_action :authenticate_user!

    def index
      @demarches = accessible_demarches
    end

    private

    # Reproduit le scoping utilisé ailleurs : User has_and_belongs_to_many :demarches.
    # En fallback (association non disponible ou vide pour un super-utilisateur),
    # on retourne toutes les démarches — cohérent avec l'absence de scoping dans
    # Admin::SchemaBuilderController et les anciens BaserowSchema/GristSchema.
    def accessible_demarches
      scoped = current_user.demarches.order(:libelle)
      scoped.any? ? scoped : Demarche.order(:libelle)
    rescue NoMethodError
      Demarche.order(:libelle)
    end
  end
end
