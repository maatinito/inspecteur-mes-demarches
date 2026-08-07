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

    context 'amount given by a NUMERIC annotation (regression: aliased value field)', vcr: { cassette_name: 'payzen_payment_order_1' } do
      let(:order) { created_order }
      let(:task) { controle.when_asked.first }
      before do
        allow(Payzen::API).to receive(:new).and_return(payzen_api)
        allow(ScheduledTask).to receive(:enqueue)
        # Champ numérique : `value` est aliasé en `int_value` dans le fragment GraphQL,
        # donc l'appeler directement lève `unfetched field 'value'`.
        numeric_field = double('IntegerNumberChamp', __typename: 'IntegerNumberChamp', int_value: '100')
        allow(numeric_field).to receive(:value).and_raise("unfetched field `value'")
        allow(controle).to receive(:annotation).and_call_original
        allow(controle).to receive(:annotation).with(controle.params[:champ_montant]).and_return(numeric_field)
      end

      it 'reads the amount via the typed accessor without raising' do
        allow(task).to receive(:process_order)
        expect(SetAnnotationValue).to receive(:set_value).with(dossier, instructeur, controle.params[:champ_ordre_de_paiement], order_id)
        expect { subject }.not_to raise_error
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

  # Une tâche rejouée par ScheduledTaskJob porte des params figés en base : ils peuvent
  # être périmés (mode_test, clés) alors que le YAML a changé depuis. Elle doit donc se
  # contenter de vérifier l'ordre existant, jamais en créer un nouveau.
  context 'rejeu par une tâche planifiée' do
    let(:order) { created_order }
    let(:controle) { FactoryBot.build :payment_order, :with_fixed_amount, scheduled: true }

    before { allow(Payzen::API).to receive(:new).and_return(payzen_api) }

    context 'sans ordre en cours', vcr: { cassette_name: 'payzen_payment_order_3' } do
      it "ne crée pas d'ordre de paiement" do
        expect(payzen_api).not_to receive(:create_url_order)
        expect(SetAnnotationValue).not_to receive(:set_value)
        expect(ScheduledTask).not_to receive(:enqueue)
        expect(SendMessage).not_to receive(:deliver_message)
        subject
      end
    end
  end

  # PSP_1000 signifie « ordre inconnu de cette boutique dans ce mode ». PayZen cloisonne
  # les ordres entre test et production : un ordre créé avec l'autre clé est invisible ici.
  context 'ordre introuvable dans le mode courant', vcr: { cassette_name: 'payzen_payment_order_2' } do
    let(:order_id) { 'c4402491f1f048509bdbcdc846505f86' }
    let(:not_found) { { errorCode: 'PSP_1000', errorMessage: 'Payment order not found' } }
    let(:current_api) { double('Payzen::API', get_order: not_found) }

    # clés string : c'est ce que produit le YAML en production (cf. payment_order.rb:23-25)
    let(:controle) do
      Payzen::PaymentOrder.new(
        'etat_du_dossier' => 'en_construction', 'mode_test' => 'oui', 'reference' => 'reference',
        'montant' => '100', 'champ_ordre_de_paiement' => 'Demande de paiement', 'message' => 'message',
        'boutique' => '1234', 'cle' => 'prodpassword_x', 'cle_de_test' => 'testpassword_y'
      )
    end

    before do
      allow(Payzen::API).to receive(:new).with('1234', 'testpassword_y').and_return(current_api)
      allow(Payzen::API).to receive(:new).with('1234', 'prodpassword_x').and_return(other_api)
      field = controle.dossier_annotations(dossier, controle.params[:champ_ordre_de_paiement]).first
      allow(field).to receive(:value).and_return(order_id)
    end

    context "et présent dans l'autre mode" do
      let(:other_api) { double('Payzen::API', get_order: { paymentOrderStatus: 'RUNNING' }) }

      it 'signale la discordance de mode et le champ à vider' do
        expect { subject }.to raise_error(
          StandardError,
          /existe en mode production alors que la configuration est en mode test.*Demande de paiement/m
        )
      end
    end

    context "et absent de l'autre mode" do
      let(:other_api) { double('Payzen::API', get_order: not_found) }

      it "conserve le message d'erreur générique" do
        expect { subject }.to raise_error(
          StandardError, 'Erreur PayZen en vérifiant un ordre de paiement: PSP_1000 - Payment order not found'
        )
      end
    end
  end
end
