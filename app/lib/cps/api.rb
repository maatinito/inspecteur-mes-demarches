# frozen_string_literal: true

require 'json'
module Cps
  class API
    RESOURCE_NAME = 'covid/assures/coherenceDnDdn/multiples'
    API_CPS_AUTH = ENV.fetch('API_CPS_AUTH', 'https://connect.cps.pf/auth/realms/TatouAssures/protocol/openid-connect/token')
    API_CPS_URL = ENV.fetch('API_CPS_URL', 'https://tatouapi.cps.pf')

    TIMEOUT = 3
    TWO_DIGIT_YEAR = /^\s*(?<day>\d\d?)\D(?<month>\d\d?)\D(?<year>\d\d?)\s*$/

    # dn_pairs must be of the form { DN ==> BirthDate }
    def verify(dn_pairs)
      call(RESOURCE_NAME, dn_pairs)
    end

    private

    def call(resource_name, dn_pairs)
      url = url(resource_name)
      json_dn = json_dn(dn_pairs)
      response = Typhoeus.post(url, body: json_dn, timeout: TIMEOUT, ssl_verifypeer: true, verbose: false, headers:)

      if response.success?
        JSON.parse(response.body)['datas']
        # puts "#{json_dn} ==> #{result}"

      elsif response.code&.between?(401, 499)
        raise APIEntreprise::API::ResourceNotFound, response
      else
        Rails.logger.error("Unable to contact CPS API: response code #{response.code} url=#{url} called with #{json_dn}")
        raise APIEntreprise::API::RequestFailed, response
      end
    end

    def url(resource_name)
      [API_CPS_URL, resource_name].join('/')
    end

    def json_dn(dn_pairs)
      dn_pairs = dn_pairs.to_h do |dn, date|
        if date.is_a? String
          begin
            if (m = date.match(TWO_DIGIT_YEAR))
              prefix = m[:year].to_i + 2000 <= Date.today.year ? '20' : '19'
              date = "#{m[:day]}/#{m[:month]}/#{prefix}#{m[:year]}"
            end
            date = Date.parse(date)
          rescue StandardError => e
            date = Date.parse('01/01/1800')
          end
        end
        if date.is_a? Date
          [dn, date.strftime('%d/%m/%Y')]
        else
          raise ArgumentError "Invalid date format #{date}"
        end
      end
      {
        datas: dn_pairs
      }.to_json
    end

    def headers
      {
        Authorization: "Bearer #{access_token}",
        'Content-Type': 'application/json'
      }
    end

    def access_token
      if !@expires_at || Time.zone.now >= @expires_at
        body = parse_response_body(fetch_access_token)
        if body[:error]
          Rails.logger.error "Unable to connect to CPS's keycloak : #{body[:error_description]} url=#{API_CPS_AUTH}"
          return ''
        end
        @access_token = body[:access_token]
        @expires_at = Time.zone.now + body[:expires_in].seconds - 1.minute
      end
      @access_token
    end

    def parse_response_body(response)
      JSON.parse(response.body, symbolize_names: true)
    end

    def fetch_access_token
      Typhoeus.post(API_CPS_AUTH, body: auth_body)
    end

    def auth_body
      {
        grant_type: 'password',
        client_id: Rails.application.secrets.api_cps[:client_id],
        client_secret: Rails.application.secrets.api_cps[:client_secret],
        username: Rails.application.secrets.api_cps[:username],
        password: Rails.application.secrets.api_cps[:password],
        scope: 'openid'
      }
    end
  end
end
