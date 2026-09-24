# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe Dbs::InviterEleveurs do
  include ActiveSupport::Testing::TimeHelpers

  let(:task) do
    described_class.new(
      demarche_engagement: 'engagements-poussins',
      eleveurs: 'Liste des éleveurs',
      invitations_envoyees: 'Invitations envoyées',
      objet: 'Engagement poussins — {nom_eleveur}',
      message: 'Bonjour {nom_eleveur}, lot {number} : {lien}',
      prerempli: { 197_027 => 'number', 197_035 => 'Quantité de poussins', 197_038 => "Nom et Prénom de l'éleveur",
                   197_047 => "Téléphone de l'éleveur" },
      importateur_eleveur: { si: "Lieux d'isolement", vaut: 'Chez vous', nom: '{Prénom du responsable} {Nom du responsable}',
                             email: '{usager.email}', telephone: '{Téléphone}', quantite: '{Quantité de poussins isolés chez vous}' }
    )
  end
  let(:demarche) { instance_double(Demarche, instructeur: 'robot') }

  def champ(label, value, typename: 'TextChamp')
    double(label, label:, __typename: typename, value:, string_value: value, int_value: value)
  end

  def row(nom, email, tel)
    double("Row #{nom}", champs: [champ("Nom et Prénom de l'éleveur", nom),
                                  champ("Email de l'éleveur", email),
                                  champ("Téléphone de l'éleveur", tel)])
  end

  let(:rows) { [row('Manutere TERE', 'manutere@exemple.pf', '87 54 65 75'), row('Vaimiti HOA', 'Vaimiti@exemple.pf', '88 65 25 62')] }
  let(:bloc) { double('RepetitionChamp', label: 'Liste des éleveurs', __typename: 'RepetitionChamp', rows:) }
  let(:envois) { champ('Invitations envoyées', envois_texte, typename: 'TextChamp') }
  let(:envois_texte) { nil }
  let(:lieux_values) { [] }
  let(:lieux) { double('Lieux', label: "Lieux d'isolement", __typename: 'MultipleDropDownListChamp', values: lieux_values) }
  let(:dossier) { double('Dossier', number: 654_000, state: 'en_instruction', champs: [bloc, lieux], annotations: [envois]) }
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
      dossier, 'robot', 'Invitations envoyées', 'manutere@exemple.pf — envoyé le 22/09/2026 14:05'
    )
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

  context 'quand deux lignes du bloc portent le même courriel (casse différente)' do
    let(:rows) do
      [row('Manutere TERE', 'manutere@exemple.pf', '87 54 65 75'),
       row('Manutere DOUBLON', 'MANUTERE@exemple.pf', '87 00 00 00'),
       row('Vaimiti HOA', 'Vaimiti@exemple.pf', '88 65 25 62')]
    end
    let(:textes_annotation) { [] }

    before do
      allow(SetAnnotationValue).to receive(:set_value) do |*args|
        textes_annotation << args.last
        true
      end
    end

    it "n'invite qu'une fois un courriel dupliqué dans le bloc" do
      task.process(demarche, dossier)

      expect(NotificationMailer).to have_received(:with).twice
      expect(textes_annotation).to all(satisfy { |texte| texte.scan('manutere@exemple.pf').size <= 1 })
    end
  end

  context "quand l'importateur isole une partie du lot chez lui" do
    let(:lieux_values) { ['Chez vous'] }
    let(:dossier) do
      double('Dossier', number: 654_000, state: 'en_instruction',
                        usager: double('Usager', email: 'chanel@exemple.pf'),
                        champs: [bloc, lieux, champ('Nom du responsable', 'MOLLARD'), champ('Prénom du responsable', 'Vaihere'),
                                 champ('Téléphone', '40 50 60 70'), champ('Quantité de poussins isolés chez vous', 700, typename: 'IntegerNumberChamp')],
                        annotations: [envois])
    end

    it "invite aussi l'importateur quand Lieux d'isolement contient Chez vous" do
      task.process(demarche, dossier)

      expect(NotificationMailer).to have_received(:with).exactly(3).times
      expect(NotificationMailer).to have_received(:with).with(hash_including(
                                                                recipients: 'chanel@exemple.pf',
                                                                message: a_string_including('champ_Q2hhbXAtMTk3MDM1=700', 'champ_Q2hhbXAtMTk3MDM4=Vaihere+MOLLARD')
                                                              ))
    end
  end

  context "quand l'écriture de la trace échoue au premier envoi" do
    before { allow(SetAnnotationValue).to receive(:set_value).and_raise('boom') }

    it "propage l'erreur et n'envoie pas le courriel suivant" do
      expect { task.process(demarche, dossier) }.to raise_error('boom')
      expect(NotificationMailer).to have_received(:with).once
    end
  end

  it 'ne fait rien hors de l état en_instruction' do
    allow(dossier).to receive(:state).and_return('en_construction')
    task.process(demarche, dossier)
    expect(NotificationMailer).not_to have_received(:with)
  end

  context "quand l'annotation de trace est introuvable sur le dossier" do
    let(:dossier) { double('Dossier', number: 654_000, state: 'en_instruction', champs: [bloc], annotations: []) }

    it "refuse d'inviter, pour ne jamais renvoyer en boucle" do
      expect { task.process(demarche, dossier) }.to raise_error(/Invitations envoyées.*654000/)
      expect(NotificationMailer).not_to have_received(:with)
    end
  end
end
# rubocop:enable Metrics/BlockLength
