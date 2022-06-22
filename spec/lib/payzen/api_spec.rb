# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payzen::API do
  let(:api) { Payzen::API.new }
  let(:empty_customer) { api.customer('example@company.com') }

  before do
    # Do nothing
  end

  after do
    # Do nothing
  end

  context 'create_url_order', vcr: { cassette_name: 'payzen_create_url_order' } do
    subject { api.create_url_order(amount, reference, expiration_date:, customer:) }
    let(:amount) { 10_000 }
    let(:reference) { 'my-reference' }
    let(:expiration_date) { nil }
    let(:customer) { nil }

    context 'parameters are good & minimal' do
      it 'succeeds' do
        expect(subject).to include(
          amount:,
          currency: 'XPF',
          paymentOrderStatus: 'RUNNING',
          orderId: reference
        )
      end
    end
  end
end
