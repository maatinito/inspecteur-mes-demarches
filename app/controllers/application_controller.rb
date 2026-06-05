# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Réservation aux administrateurs. Utilisé sur les controllers d'outil système
  # (schema builder) qui manipulent le méta-modèle Baserow via le master token.
  # Un user non admin atteignant un de ces controllers est redirigé avec un flash.
  def require_admin!
    return if current_user&.admin?

    redirect_to root_path, alert: 'Cette section est réservée aux administrateurs.'
  end
end
