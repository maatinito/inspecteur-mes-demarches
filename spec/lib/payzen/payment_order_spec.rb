# frozen_string_literal: true

require 'rails_helper'

class TestOrderTask < Payzen::Task
  def process_order(demarche, dossier, order); end
end

RSpec.describe Payzen::PaymentOrder do
  let(:dossier_nb) { 337_794 }
  let(:dossier) { DossierActions.on_dossier(dossier_nb) }
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
  let(:unknown_order) { base_order.merge(errorCode: 'PSP_010', errorMessage: 'transaction not found') }
  let(:order_id) { order[:paymentOrderId] }

  let(:payzen_api) { double('Payzen::API', create_url_order: order, get_order: order) }

  before do
    allow(demarche).to receive(:instructeur).and_return(instructeur)
    allow(SendMessage).to receive(:deliver_message)
  end

  subject do
    controle.process(demarche, dossier)
    controle
  end

  context 'control without way to compute amounr' do
    let(:controle) { FactoryBot.build :payment_order, :without_amount }
    it 'should be invalid' do
      expect(controle.valid?).to be_falsey
    end
  end

  context 'dossier amount not set', vcr: { cassette_name: 'payzen_payment_order_1' } do
    it 'should not trigger payment' do
      expect(SetAnnotationValue).not_to receive(:set_value)
      subject
    end
  end

  context 'dossier in bad state', vcr: { cassette_name: 'payzen_payment_order_1' } do
    it 'should not trigger payment' do
      expect(dossier).to receive(:state).and_return('en_instruction')
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

    context "amount given by dossier's annotation" do
      before do
        allow(Payzen::API).to receive(:new).and_return(payzen_api)
        field = controle.dossier_annotations(dossier, controle.params[:champ_montant]).first
        expect(field).to receive(:value).and_return('100')
      end

      context 'and order not requested', vcr: { cassette_name: 'payzen_payment_order_1' } do
        let(:order) { created_order }
        let(:task) { controle.when_asked.first }
        it 'should trigger payment order' do
          allow(task).to receive(:process_order).with(demarche, dossier, order)
          expect(SetAnnotationValue).to receive(:set_value).with(dossier, instructeur, controle.params[:champ_ordre_de_paiement], order_id)
          expect(ScheduledTask).to receive(:enqueue).with(dossier.number, Payzen::PaymentOrder, controle.params, controle.check_delay)
          expect(SendMessage).to receive(:deliver_message).with(dossier, instructeur, controle.params[:message])
          subject
        end
      end

      context 'and order requested', vcr: { cassette_name: 'payzen_payment_order_1' } do
        let(:order) { created_order }
        let(:task) { controle.when_asked.first }
        it "should NOT trigger 'quand_demandé' tasks" do
          field = controle.dossier_annotations(dossier, controle.params[:champ_ordre_de_paiement]).first
          allow(field).to receive(:value).and_return(order_id)
          allow(task).to receive(:process_order)

          expect(SetAnnotationValue).not_to receive(:set_value)
          expect(ScheduledTask).to receive(:enqueue).with(dossier.number, Payzen::PaymentOrder, controle.params, controle.check_delay)
          expect(SendMessage).not_to receive(:deliver_message)
          expect(task).not_to receive(:process_order)
          subject
        end
      end

      context 'and order refused', vcr: { cassette_name: 'payzen_payment_order_1' } do
        let(:order) { refused_order }
        let(:task) { controle.when_asked.first }
        it "should NOT trigger 'quand_demandé' tasks" do
          field = controle.dossier_annotations(dossier, controle.params[:champ_ordre_de_paiement]).first
          allow(field).to receive(:value).and_return(order_id)
          allow(task).to receive(:process_order)

          expect(SetAnnotationValue).not_to receive(:set_value)
          expect(ScheduledTask).to receive(:enqueue).with(dossier.number, Payzen::PaymentOrder, controle.params, controle.check_delay)
          expect(SendMessage).not_to receive(:deliver_message)
          expect(task).not_to receive(:process_order)
          subject
        end
      end

      context 'and order paid', vcr: { cassette_name: 'payzen_payment_order_1' } do
        let(:order) { paid_order }
        let(:task) { controle.when_paid.first }
        it "should trigger 'quand_payé' tasks" do
          field = controle.dossier_annotations(dossier, controle.params[:champ_ordre_de_paiement]).first
          allow(field).to receive(:value).and_return(order_id)
          allow(task).to receive(:process_order)

          expect(SetAnnotationValue).not_to receive(:set_value)
          expect(ScheduledTask).not_to receive(:enqueue)
          expect(task).to receive(:process_order)
          subject
        end
      end

      context 'and order expired', vcr: { cassette_name: 'payzen_payment_order_1' } do
        let(:order) { expired_order }
        let(:task) { controle.when_expired.first }
        it "should trigger 'quand_payé' tasks" do
          field = controle.dossier_annotations(dossier, controle.params[:champ_ordre_de_paiement]).first
          allow(field).to receive(:value).and_return(order_id)
          allow(task).to receive(:process_order)

          expect(SetAnnotationValue).not_to receive(:set_value)
          expect(ScheduledTask).not_to receive(:enqueue)
          expect(task).to receive(:process_order)
          subject
        end
      end

      context 'and order unknown', vcr: { cassette_name: 'payzen_payment_order_2' } do
        include ActiveJob::TestHelper

        let(:order) { unknown_order }
        let(:task) { controle.when_expired.first }
        it 'should be ignored' do
          field = controle.dossier_annotations(dossier, controle.params[:champ_ordre_de_paiement]).first
          allow(field).to receive(:value).and_return('c4402491f1f048509bdbcdc846505f80') # invalid id
          allow(demarche).to receive(:id).and_return(1718)
          allow(task).to receive(:process_order)
          expect(SetAnnotationValue).not_to receive(:set_value)
          expect(ScheduledTask).not_to receive(:enqueue)
          expect(task).not_to receive(:process_order)
          expect { subject }.to raise_error StandardError, 'Erreur PayZen en vérifiant un ordre de paiement: PSP_010 - transaction not found'
        end
      end
    end

    context 'amount given configuration' do
      let(:controle) do
        FactoryBot.build :payment_order, :with_fixed_amount, quand_demandé: test_order_task, quand_payé: test_order_task, quand_expiré: test_order_task
      end
      before do
        allow(Payzen::API).to receive(:new).and_return(payzen_api)
      end

      context 'and order not requested', vcr: { cassette_name: 'payzen_payment_order_3' } do
        let(:order) { created_order }
        let(:task) { controle.when_asked.first }
        it 'should trigger payment order' do
          allow(task).to receive(:process_order)
          expect(SetAnnotationValue).to receive(:set_value).with(dossier, instructeur, controle.params[:champ_ordre_de_paiement], order_id)
          expect(ScheduledTask).to receive(:enqueue).with(dossier.number, Payzen::PaymentOrder, controle.params, controle.check_delay)
          expect(SendMessage).to receive(:deliver_message).with(dossier, instructeur, controle.params[:message])
          expect(task).to receive(:process_order).with(demarche, dossier, order)
          subject
        end
      end
    end
  end
end
