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

    # Scope strict : un utilisateur ne voit QUE les démarches dont il est
    # instructeur (lien demarches_users peuplé par update_instructeurs au
    # moment de la vérification). Pas de fallback Demarche.all — ce serait
    # un trou de sécurité (un auto-inscrit verrait toutes les démarches).
    def accessible_demarches
      current_user.demarches.order(:libelle)
    end
  end
end
