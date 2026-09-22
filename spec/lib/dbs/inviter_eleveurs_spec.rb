# spec/lib/dbs/inviter_eleveurs_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dbs::InviterEleveurs do
  include ActiveSupport::Testing::TimeHelpers

  let(:task) do
    described_class.new(
      demarche_engagement: 'engagements-poussins',
      champ_eleveurs: 'Liste des éleveurs',
      annotation_envois: 'Invitations envoyées',
      objet: 'Engagement poussins — {nom_eleveur}',
      message: 'Bonjour {nom_eleveur}, lot {number} : {lien}',
      prerempli: { 197_027 => 'number', 197_038 => "Nom et Prénom de l'éleveur", 197_047 => "Téléphone de l'éleveur" }
    )
  end
  let(:demarche) { instance_double(Demarche, instructeur: 'robot') }

  def champ(label, value, typename: 'TextChamp')
    double(label, label:, __typename: typename, value:, string_value: value)
  end

  def row(nom, email, tel)
    double("Row #{nom}", champs: [champ("Nom et Prénom de l'éleveur", nom),
                                  champ("Email de l'éleveur", email),
                                  champ("Téléphone de l'éleveur", tel)])
  end

  let(:rows) { [row('Manutere TERE', 'manutere@exemple.pf', '87 54 65 75'), row('Vaimiti HOA', 'Vaimiti@exemple.pf', '88 65 25 62')] }
  let(:bloc) { double('RepetitionChamp', label: 'Liste des éleveurs', __typename: 'RepetitionChamp', rows:) }
  let(:envois) { champ('Invitations envoyées', envois_texte, typename: 'TextareaChamp') }
  let(:envois_texte) { nil }
  let(:dossier) { double('Dossier', number: 654_000, state: 'en_instruction', champs: [bloc], annotations: [envois]) }
  let(:mail) { double('Mail', deliver_later: true) }

  before do
    allow(MesDemarches).to receive(:public_url).and_return('https://md.test')
    allow(NotificationMailer).to receive(:with).and_return(double('Mailer', user_mail: mail))
    allow(SetAnnotationValue).to receive(:set_value).and_return(true)
    travel_to Time.zone.local(2026, 9, 22, 14, 5)
  end

  after { travel_back }

  it 'envoie un courriel prérempli à chaque éleveur et trace les envois' do
    task.process(demarche, dossier)

    expect(NotificationMailer).to have_received(:with).with(
      subject: 'Engagement poussins — Manutere TERE',
      message: 'Bonjour Manutere TERE, lot 654000 : https://md.test/commencer/engagements-poussins' \
               '?champ_Q2hhbXAtMTk3MDI3=654000&champ_Q2hhbXAtMTk3MDM4=Manutere+TERE&champ_Q2hhbXAtMTk3MDQ3=87+54+65+75',
      recipients: 'manutere@exemple.pf'
    )
    expect(NotificationMailer).to have_received(:with).with(hash_including(recipients: 'vaimiti@exemple.pf'))
    expect(SetAnnotationValue).to have_received(:set_value).with(
      dossier, 'robot', 'Invitations envoyées',
      "manutere@exemple.pf — envoyé le 22/09/2026 14:05\nvaimiti@exemple.pf — envoyé le 22/09/2026 14:05"
    )
    expect(task.dossier_updated?).to be true
  end

  context 'quand un éleveur a déjà été invité' do
    let(:envois_texte) { 'manutere@exemple.pf — envoyé le 20/09/2026 09:00' }

    it "n'invite que les nouveaux et conserve les lignes existantes" do
      task.process(demarche, dossier)

      expect(NotificationMailer).to have_received(:with).once
      expect(NotificationMailer).to have_received(:with).with(hash_including(recipients: 'vaimiti@exemple.pf'))
      expect(SetAnnotationValue).to have_received(:set_value).with(
        dossier, 'robot', 'Invitations envoyées',
        "manutere@exemple.pf — envoyé le 20/09/2026 09:00\nvaimiti@exemple.pf — envoyé le 22/09/2026 14:05"
      )
    end
  end

  context 'quand tout le monde a déjà été invité' do
    let(:envois_texte) { "manutere@exemple.pf — envoyé le 20/09/2026 09:00\nvaimiti@exemple.pf — envoyé le 20/09/2026 09:00" }

    it "n'envoie rien et ne touche pas au dossier" do
      task.process(demarche, dossier)
      expect(NotificationMailer).not_to have_received(:with)
      expect(SetAnnotationValue).not_to have_received(:set_value)
      expect(task.dossier_updated?).to be false
    end
  end

  it 'ne fait rien hors de l état en_instruction' do
    allow(dossier).to receive(:state).and_return('en_construction')
    task.process(demarche, dossier)
    expect(NotificationMailer).not_to have_received(:with)
  end
end
