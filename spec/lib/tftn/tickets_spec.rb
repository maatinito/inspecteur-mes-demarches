# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tftn::Tickets do
  include ActiveSupport::Testing::TimeHelpers

  let(:demarche) do
    demarche = double(Demarche)
    allow(demarche).to receive(:instructeur).and_return(instructeur)
    demarche
  end
  let(:dossier) { Struct.new(:number, :state, :date_depot).new(438_520, 'en_instruction', Date.new(2025, 1, 1)) }
  let(:instructeur) { 'instructeur' }
  let(:nom_cours) { 'Aquarelle' }

  let(:params) do
    {
      champ_cours: 'cours',
      champ_nb_tickets: "nb tickets'",
      prix_seance: '1500',
      annotation_quota: 'Quota manuel',
      annotation_montant: 'Montant à payer',
      annotation_message_usager: 'Message explicatif'
    }
  end

  let(:controle) { described_class.new(params) }

  let(:cours_field) { { id: 1, name: 'Label du cours', type: 'text' } }
  let(:date_field) { { id: 2, name: 'Date du cours', type: 'date' } }
  let(:actif_field) { { id: 3, name: 'Actif', type: 'boolean' } }
  let(:session_fields) { [cours_field, date_field, actif_field].to_h { |field| [field[:name], field] } }

  # Champs pour la table des cours
  let(:label_cours_field) { { id: 10, name: 'Label du cours', type: 'text' } }
  let(:quota_manuel_field) { { id: 11, name: 'Quota manuel', type: 'boolean' } }
  let(:cours_table_fields) { [label_cours_field, quota_manuel_field].to_h { |field| [field[:name], field] } }

  let(:cours_results) { { 'results' => [{ 'field_11' => true }] } }

  let(:session_results) { { 'count' => 5, 'results' => Array.new(5) { |i| { 'id' => i } } } }

  let(:champ_cours) { double('ChampCours', string_value: nom_cours, blank?: false) }
  let(:champ_nb_tickets) { double('ChampNbTickets', value: 5, blank?: false) }

  subject do
    controle.process(demarche, dossier)
    controle
  end

  before do
    # Mock param_field pour retourner le champ avec le nom du cours
    allow(controle).to receive(:param_field).with(:champ_cours).and_return(champ_cours)
    allow(controle).to receive(:param_field).with(:champ_nb_tickets).and_return(champ_nb_tickets)

    # Mock pour la table des sessions
    mock_table = double('BaserowSessionsTable', fields: session_fields, list_rows: session_results)
    allow(controle).to receive(:get_baserow_table).with(Tftn::Tickets::SESSION_TABLE_ID).and_return(mock_table)

    # Mock pour l atable des cours
    mock_cours_table = double('BaserowCoursTable', fields: cours_table_fields, list_rows: cours_results)
    allow(controle).to receive(:get_baserow_table).with(Tftn::Tickets::COURS_TABLE_ID).and_return(mock_cours_table)

    # Mock pour save_annotation et save_messages
    allow(controle).to receive(:save_annotation).and_return(nil)
    allow(controle).to receive(:save_messages).and_return(nil)

    # Mock pour dossier_has_right_state
    allow(controle).to receive(:dossier_has_right_state?).and_return(true)

    # Fixer la date du jour pour les tests
    travel_to Time.zone.local(2025, 4, 10, 12, 0, 0)
  end

  after { travel_back }

  context 'lorsque tous les champs sont correctement renseignés' do
    context 'sans quota manuel' do
      let(:cours_results) { { 'results' => [{ 'field_11' => false }] } }

      it 'calcule le prix total et le stocke dans l\'annotation privée' do
        # Le prix total attendu est le nombre de séances (5) x prix par séance (1500) = 7500
        expect(controle).to receive(:save_annotation).with('Montant à payer', 7500)
        expect(controle).to receive(:save_annotation).with('Quota manuel', false)

        # Vérifier que le message usager est également stocké
        message_attendu = 'Vous avez demandé 5 tickets pour le cours Aquarelle. Le montant à payer est de 7500 XPF (5 séances à 1500 XPF).'
        expect(controle).to receive(:save_annotation).with('Message explicatif', message_attendu)

        subject
      end
    end

    context 'avec quota manuel' do
      let(:cours_results) { { 'results' => [{ 'field_11' => true }] } }

      it 'ne stocke pas le montant dans l\'annotation privée mais calcule et affiche le prix' do
        # Le montant ne doit PAS être stocké si quota manuel est true
        expect(controle).not_to receive(:save_annotation).with('Montant à payer', 7500)

        # Le quota manuel doit être sauvegardé
        expect(controle).to receive(:save_annotation).with('Quota manuel', true)

        # Le message usager doit toujours être stocké
        message_attendu = 'Vous avez demandé 5 tickets pour le cours Aquarelle. Le montant à payer est de 7500 XPF (5 séances à 1500 XPF).'
        expect(controle).to receive(:save_annotation).with('Message explicatif', message_attendu)

        subject

        # Vérifier que le message du journal contient le prix total
        messages = controle.instance_variable_get(:@msgs)
        expect(messages).to include('Nombre de séances possibles: 5, Prix unitaire: 1500 XPF, Prix total: 7500')
      end
    end
  end

  context 'avec limitation par nombre de tickets désirés' do
    let(:params) do
      {
        champ_cours: 'cours',
        prix_seance: '1500',
        champ_nb_tickets: 'nb_tickets',
        annotation_montant: 'Montant à payer',
        annotation_message_usager: 'Message explicatif',
        annotation_quota: 'Quota manuel'
      }
    end

    let(:champ_nb_tickets) do
      double('ChampNbTickets', value: '3', blank?: false)
    end

    let(:cours_results) { { 'results' => [{ 'field_11' => false }] } }

    before do
      allow(controle).to receive(:param_field).with(:champ_nb_tickets).and_return(champ_nb_tickets)
    end

    it 'limite le nombre de séances au nombre de tickets désirés' do
      # Le prix total attendu est le nombre de tickets (3) x prix par séance (1500) = 4500
      expect(controle).to receive(:save_annotation).with('Montant à payer', 4500)
      expect(controle).to receive(:save_annotation).with('Quota manuel', false)

      # Vérifier que le message usager est également stocké
      message_attendu = 'Vous avez demandé 3 tickets pour le cours Aquarelle. Le montant à payer est de 4500 XPF (3 séances à 1500 XPF).'
      expect(controle).to receive(:save_annotation).with('Message explicatif', message_attendu)

      subject
    end
  end

  context 'avec la demande de toutes les séances restantes' do
    let(:params) do
      {
        champ_cours: 'cours',
        prix_seance: '1500',
        annotation_montant: 'Montant à payer',
        champ_nb_tickets: 'nb_tickets',
        annotation_message_usager: 'Message explicatif',
        annotation_quota: 'Quota manuel'
      }
    end

    let(:champ_nb_tickets) do
      double('ChampNbTickets', value: 'Toutes les séances restantes', blank?: false)
    end

    let(:cours_results) { { 'results' => [{ 'field_11' => false }] } }

    before do
      allow(controle).to receive(:param_field).with(:champ_nb_tickets).and_return(champ_nb_tickets)
    end

    it 'utilise toutes les séances disponibles' do
      # Le prix total attendu est le nombre de séances (5) x prix par séance (1500) = 7500
      expect(controle).to receive(:save_annotation).with('Montant à payer', 7500)
      expect(controle).to receive(:save_annotation).with('Quota manuel', false)

      # Vérifier que le message usager est également stocké
      message_attendu = 'Vous avez demandé toutes les séances disponibles pour le cours Aquarelle. Le montant à payer est de 7500 XPF (5 séances à 1500 XPF).'
      expect(controle).to receive(:save_annotation).with('Message explicatif', message_attendu)

      subject
    end
  end

  context 'lorsque le champ cours est vide' do
    let(:champ_cours) do
      double('ChampCours', value: '', blank?: true)
    end

    it 'ne calcule pas de prix et enregistre un message d\'erreur' do
      expect(controle).not_to receive(:get_remaining_sessions)
      expect(controle).to receive(:save_messages).and_return(nil)

      subject
    end
  end
end
