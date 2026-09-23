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
      demarche_laissez_passer: 3899,
      champ_courriel_invitation: 'Courriel indiqué par votre importateur',
      annotation_courriel_attribution: "Courriel d'attribution",
      champ_telephone: 'Téléphone'
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
  let(:courriel_invitation) { 'vaimiti@exemple.pf' }
  let(:telephone_engagement) { '88 65 25 62' }
  let(:attribution_existante) { nil }
  let(:engagement) do
    double('Engagement', number: 655_888, state: 'en_construction', date_depot: '2026-09-15T22:00:00+00:00',
                         usager: double('Usager', email: 'Vaimiti@exemple.pf'),
                         demandeur: double('PersonneMorale', entreprise: double('Entreprise', raison_sociale: 'EARL HOA')),
                         champs: [lien, champ("Nom et prénom de l'éleveur", 'Vaimiti HOA'),
                                  champ('Courriel indiqué par votre importateur', courriel_invitation),
                                  champ('Téléphone', telephone_engagement)],
                         annotations: [champ("Courriel d'attribution", attribution_existante)])
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
    let(:courriel_invitation) { '' }
    let(:telephone_engagement) { '' }

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

  context 'quand le compte usager est absent' do
    let(:courriel_invitation) { '' }
    let(:telephone_engagement) { '' }

    it 'liste l engagement comme non attendu' do
      allow(engagement).to receive(:usager).and_return(nil)
      task.process(demarche, engagement)
      expect(SetAnnotationValue).to have_received(:set_value).with(
        laissez_passer, 'robot', 'Engagements reçus',
        'Vaimiti HOA () — dossier 655888 — déposé le 15/09/2026 — non attendu'
      )
    end
  end

  context 'quand l éleveur signe avec un autre compte que le courriel déclaré' do
    before { allow(engagement).to receive(:usager).and_return(double('Usager', email: 'autre.compte@exemple.pf')) }

    it 'rattache l engagement par le courriel prérempli et le pose en annotation' do
      task.process(demarche, engagement)

      expect(SetAnnotationValue).to have_received(:set_value).with(engagement, 'robot', "Courriel d'attribution", 'vaimiti@exemple.pf')
      expect(SetAnnotationValue).to have_received(:set_value).with(
        laissez_passer, 'robot', 'Engagements reçus',
        'Vaimiti HOA (vaimiti@exemple.pf) — dossier 655888 — déposé le 15/09/2026'
      )
      expect(SetAnnotationValue).to have_received(:set_value).with(
        laissez_passer, 'robot', 'Engagements manquants', 'Manutere TERE au 87 54 65 75 (manutere@exemple.pf)'
      )
      expect(task.dossier_updated?).to be true
    end

    context 'et que le lien a été reçu sans préremplissage' do
      let(:courriel_invitation) { '' }
      let(:telephone_engagement) { '+689 87 54 65 75' }

      it 'rattache par le téléphone concordant' do
        task.process(demarche, engagement)
        expect(SetAnnotationValue).to have_received(:set_value).with(engagement, 'robot', "Courriel d'attribution", 'manutere@exemple.pf')
        expect(SetAnnotationValue).to have_received(:set_value).with(
          laissez_passer, 'robot', 'Engagements manquants', 'Vaimiti HOA au 88 65 25 62 (vaimiti@exemple.pf)'
        )
      end
    end

    context 'et que l agent a déjà corrigé l annotation' do
      let(:courriel_invitation) { '' }
      let(:attribution_existante) { 'manutere@exemple.pf' }

      it 'respecte l annotation posée et ne la réécrit pas' do
        task.process(demarche, engagement)
        expect(SetAnnotationValue).not_to have_received(:set_value).with(engagement, anything, anything, anything)
        expect(SetAnnotationValue).to have_received(:set_value).with(
          laissez_passer, 'robot', 'Engagements reçus',
          'Vaimiti HOA (manutere@exemple.pf) — dossier 655888 — déposé le 15/09/2026'
        )
      end
    end
  end

  it 'ignore un courriel prérempli qui ne correspond à aucune ligne du lot' do
    allow(engagement).to receive(:usager).and_return(double('Usager', email: 'vaimiti@exemple.pf'))
    allow(engagement).to receive(:champs).and_return(
      [lien, champ("Nom et prénom de l'éleveur", 'Vaimiti HOA'), champ('Courriel indiqué par votre importateur', 'modifie@exemple.pf'), champ('Téléphone', '')]
    )
    task.process(demarche, engagement)
    expect(SetAnnotationValue).to have_received(:set_value).with(engagement, 'robot', "Courriel d'attribution", 'vaimiti@exemple.pf')
  end
end
# rubocop:enable Metrics/BlockLength
