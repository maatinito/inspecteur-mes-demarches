# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe Dbs::EngagementRecu do
  let(:task) do
    described_class.new(
      champ_laissez_passer: 'Numéro du dossier de laissez-passer',
      champ_eleveurs: 'Liste des éleveurs',
      annotation_recus: 'Engagements reçus',
      annotation_manquants: 'Engagements manquants',
      demarche_laissez_passer: 3899
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

  let(:recus) { champ('Engagements reçus', recus_texte, typename: 'TextChamp') }
  let(:manquants) { champ('Engagements manquants', '', typename: 'TextChamp') }
  let(:recus_texte) { '' }
  let(:laissez_passer) do
    double('LaissezPasser', number: 654_000,
                            champs: [double('Bloc', label: 'Liste des éleveurs', __typename: 'RepetitionChamp',
                                                    rows: [row('Manutere TERE', 'manutere@exemple.pf', '87 54 65 75'),
                                                           row('Vaimiti HOA', 'vaimiti@exemple.pf', '88 65 25 62')])],
                            annotations: [recus, manquants], demarche: double('Demarche', number: 3899))
  end
  let(:lien) { champ('Numéro du dossier de laissez-passer', '654000', typename: 'DossierLinkChamp') }
  let(:engagement) do
    double('Engagement', number: 655_888, state: 'en_construction', date_depot: '2026-09-15T22:00:00+00:00',
                         usager: double('Usager', email: 'Vaimiti@exemple.pf'),
                         demandeur: double('PersonneMorale', entreprise: double('Entreprise', raison_sociale: 'EARL HOA')),
                         champs: [lien, champ("Nom et prénom de l'éleveur", 'Vaimiti HOA')], annotations: [])
  end

  before do
    allow(DossierActions).to receive(:on_dossier).with(654_000).and_return(laissez_passer)
    allow(SetAnnotationValue).to receive(:set_value).and_return(true)
  end

  it 'ajoute l engagement aux reçus et retire l éleveur des manquants' do
    task.process(demarche, engagement)

    expect(SetAnnotationValue).to have_received(:set_value).with(
      laissez_passer, 'robot', 'Engagements reçus',
      'Vaimiti HOA (vaimiti@exemple.pf) — dossier 655888 — déposé le 15/09/2026'
    )
    expect(SetAnnotationValue).to have_received(:set_value).with(
      laissez_passer, 'robot', 'Engagements manquants',
      'Manutere TERE au 87 54 65 75 (manutere@exemple.pf)'
    )
  end

  context 'quand le laissez-passer a déjà des engagements' do
    let(:recus_texte) { 'Manutere TERE (manutere@exemple.pf) — dossier 654125 — déposé le 01/09/2026' }

    it 'conserve les anciens, ajoute le nouveau, et vide les manquants' do
      task.process(demarche, engagement)

      expect(SetAnnotationValue).to have_received(:set_value).with(
        laissez_passer, 'robot', 'Engagements reçus',
        "Manutere TERE (manutere@exemple.pf) — dossier 654125 — déposé le 01/09/2026\n" \
        'Vaimiti HOA (vaimiti@exemple.pf) — dossier 655888 — déposé le 15/09/2026'
      )
      expect(SetAnnotationValue).to have_received(:set_value).with(laissez_passer, 'robot', 'Engagements manquants', '')
    end
  end

  context 'quand le courriel de l engagement n est pas dans la liste du lot' do
    before { allow(engagement).to receive(:usager).and_return(double('Usager', email: 'inconnu@exemple.pf')) }

    it 'le liste quand même, marqué « non attendu », sans toucher aux manquants' do
      task.process(demarche, engagement)

      expect(SetAnnotationValue).to have_received(:set_value).with(
        laissez_passer, 'robot', 'Engagements reçus',
        'Vaimiti HOA (inconnu@exemple.pf) — dossier 655888 — déposé le 15/09/2026 — non attendu'
      )
      expect(SetAnnotationValue).to have_received(:set_value).with(
        laissez_passer, 'robot', 'Engagements manquants',
        "Manutere TERE au 87 54 65 75 (manutere@exemple.pf)\nVaimiti HOA au 88 65 25 62 (vaimiti@exemple.pf)"
      )
    end
  end

  it 'lève une erreur explicite si le laissez-passer lié est introuvable' do
    allow(DossierActions).to receive(:on_dossier).with(654_000).and_return(nil)
    expect { task.process(demarche, engagement) }.to raise_error(/654000.*655888/)
  end

  it "lève une erreur explicite si le dossier lié n'est pas un laissez-passer de la démarche attendue" do
    allow(laissez_passer).to receive(:demarche).and_return(double('Demarche', number: 1234))
    expect { task.process(demarche, engagement) }.to raise_error(/n'est pas un laissez-passer/)
  end

  it "date l'engagement au fuseau de l'application (Pacific/Tahiti), pas en UTC" do
    allow(engagement).to receive(:date_depot).and_return('2026-09-15T23:30:00-10:00')
    task.process(demarche, engagement)
    expect(SetAnnotationValue).to have_received(:set_value).with(
      laissez_passer, 'robot', 'Engagements reçus',
      'Vaimiti HOA (vaimiti@exemple.pf) — dossier 655888 — déposé le 15/09/2026'
    )
  end

  it 'ne fait rien sur un dossier refusé' do
    allow(engagement).to receive(:state).and_return('refuse')
    task.process(demarche, engagement)
    expect(DossierActions).not_to have_received(:on_dossier)
  end

  it 'ne fait rien et n interroge pas la plateforme quand aucun laissez-passer n est renseigné' do
    allow(lien).to receive(:string_value).and_return('')
    task.process(demarche, engagement)
    expect(DossierActions).not_to have_received(:on_dossier)
    expect(SetAnnotationValue).not_to have_received(:set_value)
  end

  it 'liste l engagement comme non attendu quand le compte usager est absent' do
    allow(engagement).to receive(:usager).and_return(nil)
    task.process(demarche, engagement)
    expect(SetAnnotationValue).to have_received(:set_value).with(
      laissez_passer, 'robot', 'Engagements reçus',
      'Vaimiti HOA () — dossier 655888 — déposé le 15/09/2026 — non attendu'
    )
  end
end
# rubocop:enable Metrics/BlockLength
