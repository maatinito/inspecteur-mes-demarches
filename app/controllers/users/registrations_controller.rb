# frozen_string_literal: true

# Bloque l'inscription publique (new/create). Sécurité : éviter le scénario
# phishing où un attaquant s'inscrit avec l'email d'un instructeur légitime
# (sans son consentement, via confirmation Devise envoyée à la vraie boîte
# qui peut être cliquée par réflexe) et hérite de ses démarches au prochain
# InspectJob via update_instructeurs (assignment automatique par email-match).
#
# Les actions edit/update/destroy restent disponibles pour que les utilisateurs
# légitimes puissent gérer leur profil (changement de password, etc.).
#
# Les comptes sont créés manuellement via rails console :
#   User.create!(email: '...', password: '...', confirmed_at: Time.current)
module Users
  class RegistrationsController < Devise::RegistrationsController
    def new
      block_signup
    end

    def create
      block_signup
    end

    private

    def block_signup
      redirect_to new_user_session_path, alert: 'Inscription publique désactivée. Contactez un administrateur pour obtenir un compte.'
    end
  end
end
