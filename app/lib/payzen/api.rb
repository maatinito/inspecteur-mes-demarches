# frozen_string_literal: true

require 'json'
module Payzen
  class API
    RESOURCE_NAME = 'covid/assures/coherenceDnDdn/multiples'
    HOST_URL = ENV.fetch('PAYZEN_URL', 'https://api.secure.osb.pf/api-payment/V4')
    CREATE_ORDER = 'Charge/CreatePaymentOrder'
    GET_ORDER = 'Charge/PaymentOrder/Get'

    TIMEOUT = 3

    def create_url_order(amount, reference, expiration_date:, customer:)
      call(CREATE_ORDER, order(amount, reference, url_channel, expiration_date:, customer:))
    end

    def get_order(payzen_reference)
      call(GET_ORDER, { paymentOrderId: payzen_reference })
    end

    def customer(email, billing_details = nil)
      result = {
        email:,
        billingDetails: billing_details
      }
      result[:billingDetails] = billing_details if billing_details.present?
    end

    def private_billing_details(firstname, lastname)
      {
        category: 'PRIVATE',
        firstName: firstname,
        lastName: lastname
      }
    end

    def order(amount, reference, channel, expiration_date:, customer:)
      result = {
        amount:,
        currency: 'XPF',
        channelOptions: channel,
        orderId: reference
      }
      result[:expirationDate] = expiration_date.iso8601 if expiration_date.present?
      result[:customer] = customer if customer.present?
      result
    end

    private

    def url_channel
      { channelType: 'URL' }
    end

    def call(resource_name, body)
      url = url(resource_name)
      response = Typhoeus.post(url, body: body.to_json, timeout: TIMEOUT, ssl_verifypeer: true, verbose: false, headers:)

      if response.success?
        body = parse_response_body(response)
        return body[:answer] if body[:status] == 'SUCCESS'

        raise APIEntreprise::API::Error::RequestFailed("Erreur Payzen: #{body['answer']}")
      elsif response.code&.between?(401, 499)
        raise APIEntreprise::API::Error::ResourceNotFound, response
      else
        Rails.logger.error("Unable to contact CPS API: response code #{response.code} url=#{url} called with #{body}")
        raise APIEntreprise::API::Error::RequestFailed, response
      end
    end

    def url(resource_name)
      "#{HOST_URL}/#{resource_name}"
    end

    def headers
      {
        Authorization: "Basic #{authentification}",
        'Content-Type': 'application/json'
      }
    end

    def authentification
      @authentification ||= Base64.strict_encode64("#{ENV.fetch('PAYZEN_LOGIN', nil)}:#{ENV.fetch('PAYZEN_PASSWORD', nil)}")
    end

    def parse_response_body(response)
      JSON.parse(response.body, symbolize_names: true)
    end

    def fetch_access_token
      Typhoeus.post(API_CPS_AUTH, body: auth_body)
    end
  end
end
