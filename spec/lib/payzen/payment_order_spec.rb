# frozen_string_literal: true

require 'rails_helper'

class TestOrderTask < Payzen::Task
  def process_order(demarche, dossier, order); end
end

RSpec.describe Payzen::PaymentOrder do
  let(:dossier_nb) { 303_186 }
  let(:dossier) do
    r = nil
    DossierActions.on_dossier(dossier_nb) { |d| r = d }
    r
  end
  let(:demarche) { double(Demarche) }
  let(:controle) { FactoryBot.build :payment_order }
  let(:instructeur) { 'instructeur' }
  let(:base_order) do
    {
      _type: 'V4/PaymentOrder',
      amount: 100,
      channelDetails: {
        _type: 'V4/ChannelDetails',
        channelType: 'URL'
      },
      creationDate: '2022-06-22T18:41:39+00:00',
      currency: 'XPF',
      customer: {
        _type: 'V4/Customer/Customer',
        email: 'example@company.com',
        extraDetails: {
          _type: 'V4/Customer/ExtraDetails'
        }
      },
      dataCollectionForm: false,
      expirationDate: '2022-06-23T09:59:59+00:00',
      formAction: 'PAYMENT',
      locale: 'fr_FR',
      orderId: 'reference',
      paymentOrderId: 'c4402491f1f048509bdbcdc846505f86',
      paymentOrderStatus: 'RUNNING',
      paymentReceiptEmail: 'example@company.com',
      paymentURL: 'https://secure.osb.pf/t/3m94qazq',
      strongAuthentication: 'AUTO',
      transactionDetails: {
        _type: 'V4/PaymentOrderTransactionDetails',
        cardDetails: {
          _type: 'V4/CardDetails',
          captureDelay: 0,
          manualValidation: 'NO'
        }
      }
    }
  end

  let(:created_order) { base_order.merge(expirationDate: 1.hour.since.iso8601, paymentOrderStatus: 'RUNNING') }
  let(:expired_order) { base_order.merge(expirationDate: 1.minute.ago.iso8601, paymentOrderStatus: 'EXPIRED') }
  let(:refused_order) { base_order.merge(expirationDate: 1.hour.since.iso8601, paymentOrderStatus: 'REFUSED') }
  let(:paid_order) { base_order.merge(expirationDate: 1.hour.since.iso8601, paymentOrderStatus: 'PAID') }
  let(:order_id) { order[:paymentOrderId] }

  let(:payzen_api) { double('Payzen::API', create_url_order: order, get_order: order) }

  before do
    allow(demarche).to receive(:instructeur).and_return(instructeur)
    allow(ScheduledTask).to receive(:enqueue)
    allow(SendMessage).to receive(:send)
    allow(SetAnnotationValue).to receive(:set_value).and_return(nil)
  end

  subject do
    controle.process(demarche, dossier)
    controle
  end

  context 'dossier amount not set', vcr: { cassette_name: 'payzen_payment_order_1' } do
    let(:amount) { 300 + 660 + 0 }
    it 'should not trigger payment' do
      expect(SetAnnotationValue).not_to receive(:set_value)
      subject
    end
  end

  context 'dossier en_construction', vcr: { cassette_name: 'payzen_payment_order_1' } do
    let(:amount) { 300 + 660 + 0 }
    it 'should not trigger payment' do
      expect(dossier).to receive(:state).and_return('en_construction')
      expect(SetAnnotationValue).not_to receive(:set_value)
      subject
    end
  end

  context 'dossier ready' do
    let(:test_order_task) { [{ 'test_order_task' => {} }] }
    let(:controle) do
      FactoryBot.build :payment_order,
                       quand_demandé: test_order_task,
                       quand_payé: test_order_task,
                       quand_expiré: test_order_task
    end
    before do
      allow(Payzen::API).to receive(:new).and_return(payzen_api)
      field = controle.dossier_annotations(dossier, controle.params[:champ_montant]).first
      expect(field).to receive(:value).and_return('100')
    end

    context 'and order not requested', vcr: { cassette_name: 'payzen_payment_order_1' } do
      let(:order) { created_order }
      let(:task) { controle.when_asked.first }
      it 'should trigger payment order' do
        allow(task).to receive(:process_order)
        subject
        expect(SetAnnotationValue).to have_received(:set_value).with(dossier, instructeur, controle.params[:champ_ordre_de_paiement], order_id)
        expect(ScheduledTask).to have_received(:enqueue).with(dossier.number, Payzen::PaymentOrder, controle.params, Payzen::PaymentOrder::CHECK_DELAY)
        expect(SendMessage).to have_received(:send).with(dossier.id, instructeur, controle.params[:message])
        expect(task).to have_received(:process_order).with(demarche, dossier, order)
      end
    end

    context 'and order requested', vcr: { cassette_name: 'payzen_payment_order_1' } do
      let(:order) { created_order }
      let(:task) { controle.when_asked.first }
      it "should NOT trigger 'quand_demandé' tasks" do
        field = controle.dossier_annotations(dossier, controle.params[:champ_ordre_de_paiement]).first
        allow(field).to receive(:value).and_return(order_id)
        allow(task).to receive(:process_order)

        subject
        expect(SetAnnotationValue).not_to have_received(:set_value)
        expect(ScheduledTask).to have_received(:enqueue).with(dossier.number, Payzen::PaymentOrder, controle.params, Payzen::PaymentOrder::CHECK_DELAY)
        expect(SendMessage).not_to have_received(:send)
        expect(task).not_to have_received(:process_order)
      end
    end

    context 'and order refused', vcr: { cassette_name: 'payzen_payment_order_1' } do
      let(:order) { refused_order }
      let(:task) { controle.when_asked.first }
      it "should NOT trigger 'quand_demandé' tasks" do
        field = controle.dossier_annotations(dossier, controle.params[:champ_ordre_de_paiement]).first
        allow(field).to receive(:value).and_return(order_id)
        allow(task).to receive(:process_order)

        subject
        expect(SetAnnotationValue).not_to have_received(:set_value)
        expect(SendMessage).not_to have_received(:send)
        expect(ScheduledTask).to have_received(:enqueue).with(dossier.number, Payzen::PaymentOrder, controle.params, Payzen::PaymentOrder::CHECK_DELAY)
        expect(task).not_to have_received(:process_order)
      end
    end

    context 'and order paid', vcr: { cassette_name: 'payzen_payment_order_1' } do
      let(:order) { paid_order }
      let(:task) { controle.when_paid.first }
      it "should trigger 'quand_payé' tasks" do
        field = controle.dossier_annotations(dossier, controle.params[:champ_ordre_de_paiement]).first
        allow(field).to receive(:value).and_return(order_id)
        allow(task).to receive(:process_order)

        subject
        expect(SetAnnotationValue).not_to have_received(:set_value)
        expect(ScheduledTask).not_to have_received(:enqueue)
        expect(task).to have_received(:process_order)
      end
    end

    context 'and order expired', vcr: { cassette_name: 'payzen_payment_order_1' } do
      let(:order) { expired_order }
      let(:task) { controle.when_expired.first }
      it "should trigger 'quand_payé' tasks" do
        field = controle.dossier_annotations(dossier, controle.params[:champ_ordre_de_paiement]).first
        allow(field).to receive(:value).and_return(order_id)
        allow(task).to receive(:process_order)

        subject
        expect(SetAnnotationValue).not_to have_received(:set_value)
        expect(ScheduledTask).not_to have_received(:enqueue)
        expect(task).to have_received(:process_order)
      end
    end
  end
end
