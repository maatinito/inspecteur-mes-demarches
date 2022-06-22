# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payzen::API do
  let(:api) { Payzen::API.new }
  let(:amount) { 10_000 }
  let(:reference) { 'my-reference' }
  let(:expiration_date) { nil }
  let(:customer) { nil }

  context 'create_url_order' do
    subject { api.create_url_order(amount, reference, expiration_date:, customer:) }

    context 'minimal parameters', vcr: { cassette_name: 'payzen_create_url_order 1' } do
      it 'succeeds' do
        expect(subject).to include(
          amount:,
          currency: 'XPF',
          paymentOrderStatus: 'RUNNING',
          orderId: reference
        )
      end
    end

    context 'with minimal customer', vcr: { cassette_name: 'payzen_create_url_order 2' } do
      let(:customer) { api.customer('example@company.com') }
      it 'succeeds' do
        expect(subject).to include(
          amount:,
          currency: 'XPF',
          paymentOrderStatus: 'RUNNING',
          orderId: reference,
          customer: a_hash_including(customer)
        )
      end
    end

    context 'with customer', vcr: { cassette_name: 'payzen_create_url_order 3' } do
      let(:customer) { api.customer('example@company.com', api.private_billing_details('firstname', 'lastname')) }
      it 'succeeds' do
        expect(subject).to include(
          amount:,
          currency: 'XPF',
          paymentOrderStatus: 'RUNNING',
          orderId: reference
        )
        expect(subject[:customer]).to include(
          email: customer[:email],
          billingDetails: a_hash_including(customer[:billingDetails])
        )
      end
    end

    context 'with expiration date', vcr: { cassette_name: 'payzen_create_url_order 4' } do
      let(:customer) { api.customer('example@company.com', api.private_billing_details('firstname', 'lastname')) }
      let(:expiration_date) { DateTime.iso8601('2022-06-22T19:45:25Z') }
      it 'succeeds' do
        expect(DateTime.iso8601(subject[:expirationDate])).to eq(expiration_date.utc)
      end
    end

    context 'invalid amount', vcr: { cassette_name: 'payzen_create_url_order 5' } do
      let(:amount) { -1 }
      it 'should fail' do
        expect { subject }.to raise_error(APIEntreprise::API::Error::RequestFailed)
      end
    end
  end

  context 'get_url_order' do
    let(:order) { api.create_url_order(amount, reference) }
    subject { api.get_order(order[:paymentOrderId]) }

    context 'just created', vcr: { cassette_name: 'payzen_get_order 1' } do
      it 'succeed' do
        expect(subject).to include(paymentOrderStatus: 'RUNNING')
      end
    end
  end
end
