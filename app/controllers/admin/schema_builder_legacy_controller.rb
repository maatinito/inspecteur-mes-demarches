# frozen_string_literal: true

module Admin
  # Page de transition pour les anciennes URLs `/admin/baserow_schema*` et
  # `/admin/grist_schema*`. Liste les démarches accessibles à l'utilisateur
  # connecté et propose un lien vers le nouveau dashboard scopé par démarche.
  class SchemaBuilderLegacyController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!

    def index
      @demarches = accessible_demarches
    end

    private

    # L'accès au controller est déjà restreint aux admins via require_admin!.
    # Un admin voit toutes les démarches (sysadmin = opérateur technique,
    # pas instructeur métier).
    def accessible_demarches
      Demarche.order(:libelle)
    end
  end
end
