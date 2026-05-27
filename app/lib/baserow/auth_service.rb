# frozen_string_literal: true

require 'typhoeus'
require 'json'

module Baserow
  class AuthService
    class AuthError < StandardError; end

    # Durée de cache du JWT.
    # Baserow émet par défaut des tokens valides 60 min ; on rafraîchit avant.
    CACHE_TTL = 3000

    class << self
      # Retourne un JWT, depuis le cache si dispo et frais, sinon login.
      def jwt_token
        return @cached_token if cached?

        @cached_token = new.fetch_token
        @cached_at = Time.now.to_i
        @cached_token
      end

      # À appeler en cas de 401 pour forcer un re-login au prochain accès.
      def clear_cache
        @cached_token = nil
        @cached_at = nil
      end

      private

      def cached?
        @cached_token && @cached_at && (Time.now.to_i - @cached_at) < CACHE_TTL
      end
    end

    def initialize
      @base_url = ENV.fetch('BASEROW_URL', 'https://baserow.mes-demarches.gov.pf')
      @email = ENV.fetch('BASEROW_MASTER_EMAIL')
      @password = ENV.fetch('BASEROW_MASTER_PASSWORD')
    rescue KeyError => e
      raise AuthError, "Variable d'environnement manquante: #{e.key}"
    end

    # Login HTTP brut — pas de cache. Utilisé par AuthService.jwt_token (qui cache).
    def fetch_token
      response = make_login_request
      handle_login_response(response)
    end

    # Alias rétrocompat : `AuthService.new.jwt_token` continue à fonctionner
    # (mais bypass le cache — préférer `AuthService.jwt_token`).
    alias jwt_token fetch_token

    private

    def make_login_request
      login_data = {
        email: @email,
        password: @password
      }

      request_options = {
        method: :post,
        headers: {
          'Content-Type' => 'application/json'
        },
        body: login_data.to_json,
        timeout: 30
      }

      url = "#{@base_url}/api/user/token-auth/"
      Typhoeus::Request.new(url, request_options).run
    end

    def handle_login_response(response)
      case response.code
      when 200
        data = JSON.parse(response.body)
        token = data['access_token'] || data['token']

        raise AuthError, "Token JWT non trouvé dans la réponse: #{data.inspect}" if token.nil?

        token
      when 400
        error_data = begin
          JSON.parse(response.body)
        rescue StandardError
          { 'error' => response.body }
        end
        raise AuthError, "Credentials invalides: #{error_data.inspect}"
      when 401
        raise AuthError, 'Authentification refusée - vérifiez email/password'
      else
        error_data = begin
          JSON.parse(response.body)
        rescue JSON::ParserError
          { 'error' => response.body }
        end
        raise AuthError, "Erreur d'authentification (#{response.code}): #{error_data.inspect}"
      end
    end
  end
end
