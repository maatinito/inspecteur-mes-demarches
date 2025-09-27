# frozen_string_literal: true

require 'typhoeus'
require 'json'

module Baserow
  class AuthService
    class AuthError < StandardError; end

    def self.jwt_token
      new.jwt_token
    end

    def initialize
      @base_url = ENV.fetch('BASEROW_URL', 'https://baserow.mes-demarches.gov.pf')
      @email = ENV.fetch('BASEROW_MASTER_EMAIL')
      @password = ENV.fetch('BASEROW_MASTER_PASSWORD')
    rescue KeyError => e
      raise AuthError, "Variable d'environnement manquante: #{e.key}"
    end

    def jwt_token
      response = make_login_request
      handle_login_response(response)
    end

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
