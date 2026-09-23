# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe Dbs::EngagementRecu do
  let(:task) do
    described_class.new(
      engagement: {
        lien_laissez_passer: 'Numéro du dossier de laissez-passer',
        nom: "Nom et prénom de l'éleveur",
        telephone: 'Téléphone',
        courriel_attribution: "Courriel d'attribution"
      },
      laissez_passer: {
        demarche: 3899,
        eleveurs: 'Liste des éleveurs',
        engagements_recus: 'Engagements reçus',
        engagements_manquants: 'Engagements manquants'
      }
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
  let(:telephone_engagement) { '88 65 25 62' }
  let(:attribution_existante) { 'vaimiti@exemple.pf' }
  let(:engagement) do
    double('Engagement', number: 655_888, state: 'en_construction', date_depot: '2026-09-15T22:00:00+00:00',
                         usager: double('Usager', email: 'Vaimiti@exemple.pf'),
                         demandeur: double('PersonneMorale', entreprise: double('Entreprise', raison_sociale: 'EARL HOA')),
                         champs: [lien, champ("Nom et prénom de l'éleveur", 'Vaimiti HOA'),
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
    let(:attribution_existante) { nil }
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
    let(:attribution_existante) { nil }
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

    it "respecte l'annotation présente, préremplie ou corrigée par l'agent" do
      task.process(demarche, engagement)

      expect(SetAnnotationValue).not_to have_received(:set_value).with(engagement, anything, anything, anything)
      expect(SetAnnotationValue).to have_received(:set_value).with(
        laissez_passer, 'robot', 'Engagements reçus',
        'Vaimiti HOA (vaimiti@exemple.pf) — dossier 655888 — déposé le 15/09/2026'
      )
      expect(SetAnnotationValue).to have_received(:set_value).with(
        laissez_passer, 'robot', 'Engagements manquants', 'Manutere TERE au 87 54 65 75 (manutere@exemple.pf)'
      )
      expect(task.dossier_updated?).to be false
    end

    context 'et que le lien a été reçu sans préremplissage' do
      let(:attribution_existante) { nil }
      let(:telephone_engagement) { '+689 87 54 65 75' }

      it 'rattache par le téléphone concordant' do
        task.process(demarche, engagement)
        expect(SetAnnotationValue).to have_received(:set_value).with(engagement, 'robot', "Courriel d'attribution", 'manutere@exemple.pf')
        expect(SetAnnotationValue).to have_received(:set_value).with(
          laissez_passer, 'robot', 'Engagements manquants', 'Vaimiti HOA au 88 65 25 62 (vaimiti@exemple.pf)'
        )
      end
    end
  end

  it 'respecte une annotation préremplie même si elle n est pas dans le lot, et la marque non attendue' do
    allow(engagement).to receive(:annotations).and_return([champ("Courriel d'attribution", 'ailleurs@exemple.pf')])
    task.process(demarche, engagement)
    expect(SetAnnotationValue).to have_received(:set_value).with(
      laissez_passer, 'robot', 'Engagements reçus',
      'Vaimiti HOA (ailleurs@exemple.pf) — dossier 655888 — déposé le 15/09/2026 — non attendu'
    )
  end

  describe 'validation du paramétrage' do
    it 'refuse un sous-bloc laissez_passer incomplet' do
      t = described_class.new(engagement: { lien_laissez_passer: 'L' }, laissez_passer: { eleveurs: 'E' })
      expect(t).not_to be_valid
      expect(t.errors.join).to include('engagements_recus', 'engagements_manquants')
    end

    it 'refuse une clé inconnue dans un sous-bloc' do
      t = described_class.new(engagement: { lien_laissez_passer: 'L', courriel_invitation: 'X' },
                              laissez_passer: { eleveurs: 'E', engagements_recus: 'R', engagements_manquants: 'M' })
      expect(t).not_to be_valid
      expect(t.errors.join).to include('courriel_invitation')
    end

    it 'accepte les sous-blocs minimaux et applique les défauts' do
      t = described_class.new(engagement: { lien_laissez_passer: 'L' },
                              laissez_passer: { eleveurs: 'E', engagements_recus: 'R', engagements_manquants: 'M' })
      expect(t).to be_valid
    end
  end
end
# rubocop:enable Metrics/BlockLength
