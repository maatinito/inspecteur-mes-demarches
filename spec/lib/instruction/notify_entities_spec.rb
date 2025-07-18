# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe Instruction::NotifyEntities, type: :model do
  subject(:plugin) { described_class.new(params) }

  let(:params) do
    {
      champ_entites: 'Entités concernées',
      champ_etat_envois: 'État des envois',
      message: 'Bonjour, votre dossier {number} nécessite votre attention.',
      baserow_config: 'TEST_CONFIG',
      baserow_table_id: 123,
      objet: 'Notification dossier {number}'
    }
  end

  let(:demarche) { double('Demarche', number: 123, id: 456) }
  let(:dossier) { double('Dossier', number: 456, state: 'en_instruction') }
  let(:baserow_table) { double('BaserowTable') }
  let(:baserow_fields) do
    {
      'email' => { id: 1, name: 'Email' },
      'entité' => { id: 2, name: 'Entité' }
    }
  end

  before do
    allow(Baserow::Config).to receive(:table).and_return(baserow_table)
    allow(baserow_table).to receive(:fields).and_return(baserow_fields)
    allow(plugin).to receive(:param_annotation).and_call_original
    allow(plugin).to receive(:save_annotation)
    allow(plugin).to receive(:dossier_updated)
    allow(plugin).to receive(:instructeur_id).and_return(1)
  end

  describe '#initialize' do
    it 'sets up baserow fields correctly' do
      expect(plugin.instance_variable_get(:@email_field)).to eq(baserow_fields['email'])
      expect(plugin.instance_variable_get(:@entity_field)).to eq(baserow_fields['entité'])
    end

    context 'when email field is not found' do
      let(:baserow_fields) { { 'entité' => { id: 2, name: 'Entité' } } }

      it 'adds an error' do
        expect(plugin.errors).to include('Impossible de trouver une colonne email dans la table Baserow')
      end
    end

    context 'when entity field is not found' do
      let(:baserow_fields) { { 'email' => { id: 1, name: 'Email' } } }

      it 'adds an error' do
        expect(plugin.errors).to include('Impossible de trouver une colonne entité dans la table Baserow')
      end
    end
  end

  describe '#process' do
    let(:champ_entites) { double('ChampEntites', values: %w[ICPE JURIDIQUE]) }
    let(:champ_etat_envois) { double('ChampEtatEnvois', value: '') }

    before do
      plugin.instance_variable_set(:@dossier, dossier)
      plugin.instance_variable_set(:@demarche, demarche)
      allow(plugin).to receive(:must_check?).and_return(true)
      allow(plugin).to receive(:param_annotation).with(:champ_entites).and_return(champ_entites)
      allow(plugin).to receive(:param_annotation).with(:champ_etat_envois).and_return(champ_etat_envois)
      allow(baserow_table).to receive(:list_rows).and_return({
                                                               'results' => [
                                                                 { 'field_1' => 'john@example.com', 'field_2' => 'ICPE' },
                                                                 { 'field_1' => 'jane@example.com', 'field_2' => 'JURIDIQUE' }
                                                               ]
                                                             })
      allow(NotificationMailer).to receive(:with).and_return(double(notify_user: double(deliver_later: true)))
    end

    it 'processes notifications correctly' do
      plugin.process(demarche, dossier)

      expect(NotificationMailer).to have_received(:with).twice
      expect(plugin).to have_received(:save_annotation).with('Messages du robot', anything)
      expect(plugin).to have_received(:save_annotation).with('État des envois', anything)
    end

    context 'when must_check? returns false' do
      before do
        allow(plugin).to receive(:must_check?).and_return(false)
      end

      it 'returns early without processing' do
        plugin.process(demarche, dossier)

        expect(NotificationMailer).not_to have_received(:with)
      end
    end

    context 'when entities field is empty' do
      let(:champ_entites) { double('ChampEntites', values: []) }

      it 'returns early without processing' do
        plugin.process(demarche, dossier)

        expect(NotificationMailer).not_to have_received(:with)
      end
    end

    context 'when notifications already exist' do
      let(:champ_etat_envois) do
        double('ChampEtatEnvois', value: '[2025-01-18 14:35:12] john@example.com (ICPE)')
      end

      it 'skips already notified emails' do
        plugin.process(demarche, dossier)

        expect(NotificationMailer).to have_received(:with).once
        expect(NotificationMailer).to have_received(:with).with(
          hash_including(recipients: 'jane@example.com')
        )
      end
    end
  end

  describe '#fetch_entities' do
    let(:champ_entites) { double('ChampEntites', values: %w[ICPE JURIDIQUE]) }

    before do
      allow(plugin).to receive(:param_annotation).with(:champ_entites).and_return(champ_entites)
      allow(plugin).to receive(:add_message)
      allow(champ_entites).to receive(:blank?).and_return(false)
      allow(champ_entites.values).to receive(:blank?).and_return(false)
    end

    it 'returns entities list' do
      entities = plugin.send(:fetch_entities)

      expect(entities).to eq(%w[ICPE JURIDIQUE])
    end

    context 'when field is empty' do
      let(:champ_entites) { double('ChampEntites', values: []) }

      before do
        allow(champ_entites).to receive(:blank?).and_return(false)
        allow(champ_entites.values).to receive(:blank?).and_return(true)
      end

      it 'returns empty array' do
        entities = plugin.send(:fetch_entities)

        expect(entities).to eq([])
      end
    end
  end

  describe '#load_existing_notifications' do
    let(:champ_etat_envois) do
      double('ChampEtatEnvois', value: "[2025-01-18 14:35:12] john@example.com (ICPE)\n[2025-01-18 14:35:13] jane@example.com (JURIDIQUE)")
    end

    before do
      allow(plugin).to receive(:param_annotation).with(:champ_etat_envois).and_return(champ_etat_envois)
      allow(champ_etat_envois).to receive(:blank?).and_return(false)
    end

    it 'parses existing notifications correctly' do
      notifications = plugin.send(:load_existing_notifications)

      expect(notifications).to eq({
                                    'john@example.com' => {
                                      timestamp: '2025-01-18 14:35:12',
                                      entities: 'ICPE'
                                    },
                                    'jane@example.com' => {
                                      timestamp: '2025-01-18 14:35:13',
                                      entities: 'JURIDIQUE'
                                    }
                                  })
    end
  end

  describe '#fetch_emails_for_entities' do
    let(:entities) { %w[ICPE JURIDIQUE] }

    before do
      allow(plugin).to receive(:baserow_table).and_return(baserow_table)
      allow(plugin).to receive(:add_message)
    end

    it 'fetches emails from baserow for each entity' do
      allow(baserow_table).to receive(:list_rows).with(
        hash_including(filters: hash_including(filters: array_including(hash_including(value: 'ICPE', type: 'contains'))))
      ).and_return({
                     'results' => [{ 'field_1' => 'john@example.com' }]
                   })

      allow(baserow_table).to receive(:list_rows).with(
        hash_including(filters: hash_including(filters: array_including(hash_including(value: 'JURIDIQUE', type: 'contains'))))
      ).and_return({
                     'results' => [{ 'field_1' => 'jane@example.com' }]
                   })

      email_entity_map = plugin.send(:fetch_emails_for_entities, entities)

      expect(email_entity_map).to eq({
                                       'john@example.com' => ['ICPE'],
                                       'jane@example.com' => ['JURIDIQUE']
                                     })
    end

    context 'when person belongs to multiple entities' do
      it 'groups entities for the same email' do
        allow(baserow_table).to receive(:list_rows).and_return({
                                                                 'results' => [{ 'field_1' => 'john@example.com' }]
                                                               })

        email_entity_map = plugin.send(:fetch_emails_for_entities, entities)

        expect(email_entity_map).to eq({
                                         'john@example.com' => %w[ICPE JURIDIQUE]
                                       })
      end
    end
  end

  describe '#send_notification_to_email' do
    let(:email) { 'john@example.com' }
    let(:entities) { ['ICPE'] }

    before do
      plugin.instance_variable_set(:@dossier, dossier)
      plugin.instance_variable_set(:@demarche, demarche)
      allow(plugin).to receive(:instanciate).and_return('Processed message')
      allow(NotificationMailer).to receive(:with).and_return(double(notify_user: double(deliver_later: true)))
    end

    it 'sends notification using NotificationMailer' do
      result = plugin.send(:send_notification_to_email, email, entities)

      expect(result).to be true
      expect(NotificationMailer).to have_received(:with).with(
        dossier: dossier.number,
        demarche: demarche.id,
        recipients: email,
        subject: 'Processed message',
        message: 'Processed message'
      )
    end

    context 'when sending fails' do
      before do
        allow(NotificationMailer).to receive(:with).and_raise(StandardError.new('Send failed'))
        allow(plugin).to receive(:add_message)
      end

      it 'returns false and logs error' do
        result = plugin.send(:send_notification_to_email, email, entities)

        expect(result).to be false
        expect(plugin).to have_received(:add_message).with('Erreur lors de l\'envoi à john@example.com: Send failed')
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
