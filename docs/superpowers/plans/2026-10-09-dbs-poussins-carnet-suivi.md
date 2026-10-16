# Carnet de suivi de 21 jours (poussins) — plan de mise en œuvre

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** chaque éleveur engagé reçoit à la délivrance du laissez-passer un lien vers son carnet ; le robot surveille la mortalité (alerte 3 %), relance les silences, alimente le tableau de bord de la vétérinaire, et exécute ses décisions de visite (prolongation, levée, abattage).

**Architecture:** une nouvelle démarche « carnet » (formulaire construit par le MCP), un seul nouveau plugin (`dbs/suivi_carnet`, avec un module de calcul pur `Dbs::CarnetMortalite`), une option ajoutée à `dbs/inviter_eleveurs` pour les invitations, et du YAML pour la chaîne de visite (`daf/message`, `publipostage_v3`, `dossier_accepter`, `dossier_refuser`, `set_field`).

**Tech Stack:** Ruby 3.4 / Rails, RSpec, gem Sablon (publipostage v3), MCP `mes-demarches`, `mc` (S3 staging), LibreOffice pour les rendus de contrôle.

**Spec:** `docs/superpowers/specs/2026-10-09-dbs-poussins-carnet-suivi-design.md` (prérequis plateforme : `~/Rubymine/mes-demarches/docs/superpowers/specs/2026-10-09-formules-date-de-depot-recalcul-design.md`).

## Global Constraints

- Branche `dbs-poussins-cascade` ; livraison par fusion dans `dev` (worktree, `.env` lié) ; jamais `master`.
- Avant chaque commit Ruby : `bundle exec rubocop -A <fichiers>` puis aucune offense ; specs vertes.
- **Un seul nouveau plugin** (`dbs/suivi_carnet`) ; toute autre logique en YAML, formules ou option d'un plugin existant.
- **Ordre de déploiement** : code poussé → CI verte → robot de staging redéployé (vérifié, sinon `rollout restart`) → **seulement ensuite** publication du YAML qui l'appelle (`mc cp` depuis `storage/`).
- Gabarits Word : publiés depuis `storage/models/` ; contrôle = liste des `MERGEFIELD` + rendu de bout en bout sans champ brut ; retirer les `w:proofErr` après un enregistrement Word.
- En publipostage, les sorties de `calculs:` se lisent sous leur nom `parameterize(separator: '_')`, jamais par une colonne `champs:`.
- Seuil d'alerte `0.03`, fenêtre `3` jours, silence `4` jours, `42` jours au plus (21 + prolongation ≤ 21).
- Adresse du robot : `robot-mes-demarches@administration.gov.pf` ; alerte en staging : `clautier@idt.pf`.

## Review Focus

- Jour saisi **0 mort** : c'est une saisie (ne relance pas comme un trou) — test Task 2 (`dernier_jour_saisi`) et Task 3.
- **Trou** dans les saisies (J3 vide, J4 rempli) : le dernier jour saisi est J4, le restant de la veille ignore le trou sans planter — test Task 2.
- **Effectif restant nul** (tout le lot mort) : pas de division par zéro, pas d'alerte infinie — test Task 2.
- Carnet **clos** (accepté/refusé) rejoué par une tâche planifiée : rien n'est envoyé ni replanifié — test Task 3.
- LP accepté **sans** « Engagements reçus » (vide) : aucune invitation au carnet, pas d'erreur — test Task 1.

---

### Task 1: `dbs/inviter_eleveurs` — option `seulement_engages`, `demarche_cible`, dates préremplies

**Files:**
- Modify: `app/lib/dbs/inviter_eleveurs.rb`
- Test: `spec/lib/dbs/inviter_eleveurs_spec.rb`

**Interfaces:**
- Consumes: `Dbs::ListeEngagements.parse_recus(texte) → [Engagement(nom, email, numero, date, attendu, delivre_le)]`.
- Produces: paramètres optionnels `seulement_engages` (libellé de l'annotation texte des engagements reçus) et `demarche_cible` (alias de `demarche_engagement`, l'un des deux requis). Avec `seulement_engages`, seuls les éleveurs dont le courriel figure dans les engagements reçus sont invités, et leur ligne porte la valeur `"Numéro d'engagement"` (n° du dossier, chaîne) utilisable dans `prerempli`. Un chemin `prerempli` vers un attribut date du dossier (ex. `date_traitement`) part au format `AAAA-MM-JJ`.

- [ ] **Step 1: Write the failing tests** — ajouter à `spec/lib/dbs/inviter_eleveurs_spec.rb` :

```ruby
  context 'invitations aux carnets (seulement_engages)' do
    let(:task) do
      described_class.new(
        demarche_cible: 'carnet-poussins',
        seulement_engages: 'Engagements reçus',
        eleveurs: 'Liste des éleveurs',
        invitations_envoyees: 'Carnets envoyés',
        objet: 'Carnet — {nom_eleveur}',
        message: '{lien}',
        prerempli: { 198_100 => "Numéro d'engagement", 198_101 => 'Quantité de poussins', 198_102 => 'date_traitement' }
      )
    end
    let(:recus) do
      champ('Engagements reçus', 'Vaimiti HOA (vaimiti@exemple.pf) — dossier 655888 — déposé le 15/09/2026')
    end
    let(:dossier) do
      double('Dossier', number: 654_000, state: 'accepte', date_traitement: '2026-10-09T10:00:00-10:00',
                        champs: [bloc, lieux], annotations: [champ('Carnets envoyés', nil), recus])
    end
    let(:task_etat) { task.tap { |t| t.instance_variable_set(:@states, Set['accepte']) } }

    it 'n invite que les éleveurs engagés, avec leur numéro d engagement et J0 au format ISO' do
      task_etat.process(demarche, dossier)
      expect(NotificationMailer).to have_received(:with).once
      expect(NotificationMailer).to have_received(:with).with(
        hash_including(recipients: 'vaimiti@exemple.pf',
                       message: 'https://md.test/commencer/carnet-poussins?champ_Q2hhbXAtMTk4MTAw=655888&champ_Q2hhbXAtMTk4MTAy=2026-10-09')
      )
    end

    context 'sans engagement reçu' do
      let(:recus) { champ('Engagements reçus', nil) }

      it 'n envoie rien et ne lève pas' do
        expect { task_etat.process(demarche, dossier) }.not_to raise_error
        expect(NotificationMailer).not_to have_received(:with)
      end
    end
  end

  it 'accepte encore l ancien paramètre demarche_engagement' do
    expect(task.errors).to be_empty
  end
```

(Le lien attendu ne contient pas `Quantité de poussins` : les doubles `row` du spec n'ont pas ce champ, la valeur est vide et `PrefillURL` l'omet.)

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lib/dbs/inviter_eleveurs_spec.rb`
Expected: FAIL (`demarche_cible` inconnu / deux invitations / date au format « 09/10/2026 à 10h00 »).

- [ ] **Step 3: Implement** — dans `app/lib/dbs/inviter_eleveurs.rb` :

```ruby
    def required_fields
      super + %i[eleveurs invitations_envoyees objet message prerempli]
    end

    def authorized_fields
      super + %i[demarche_engagement demarche_cible seulement_engages email_eleveur nom_eleveur telephone_eleveur
                 quantite_eleveur importateur_eleveur]
    end
```

Dans `initialize`, après `super` :

```ruby
      @demarche_cible = @params[:demarche_cible] || @params[:demarche_engagement]
      @errors << 'demarche_cible (ou demarche_engagement) est requis sur dbs/inviter_eleveurs' if @demarche_cible.blank?
```

Remplacer `PrefillURL.build(@params[:demarche_engagement], …)` par `PrefillURL.build(@demarche_cible, …)`, le message de journal par `"Invitation envoyée à #{email} (#{@demarche_cible})"`, et dans `process` la source des éleveurs par `eleveurs_a_inviter(dossier)` :

```ruby
    # Avec seulement_engages : les seuls éleveurs ayant déposé un engagement, avec son numéro (invitation au carnet).
    def eleveurs_a_inviter(dossier)
      eleveurs = eleveurs_du_lot(dossier, @cfg)
      return eleveurs if @params[:seulement_engages].blank?

      texte = annotation(@params[:seulement_engages], warn_if_empty: false)&.value.to_s
      numeros = ListeEngagements.parse_recus(texte).to_h { |e| [e.email, e.numero.to_s] }
      eleveurs.filter_map do |e|
        numero = numeros[e[:email]]
        e.merge(valeurs: e[:valeurs].merge("Numéro d'engagement" => numero)) if numero
      end
    end

    def valeurs_prerempli(eleveur)
      @params[:prerempli].to_h do |stable_id, chemin|
        valeur = eleveur[:valeurs][chemin.to_s]
        if valeur.nil?
          brut = object_field_values(@dossier, chemin.to_s, log_empty: false).first
          # Une date (attribut du dossier : date_traitement…) reste un objet date : PrefillURL la met en AAAA-MM-JJ.
          valeur = brut.is_a?(Date) ? brut : champs_to_values([brut].compact).first
        end
        [stable_id, valeur]
      end
    end
```

`version` : `super + 4`. Mettre à jour le commentaire de classe (deux usages : engagements puis carnets).

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/lib/dbs/`
Expected: PASS (anciens exemples compris).

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/lib/dbs/inviter_eleveurs.rb spec/lib/dbs/inviter_eleveurs_spec.rb
git add app/lib/dbs/inviter_eleveurs.rb spec/lib/dbs/inviter_eleveurs_spec.rb
git commit -m "feat(dbs): inviter_eleveurs — option seulement_engages (carnets), demarche_cible, dates ISO"
```

---

### Task 2: `Dbs::CarnetMortalite` — calculs purs

**Files:**
- Create: `app/lib/dbs/carnet_mortalite.rb`
- Test: `spec/lib/dbs/carnet_mortalite_spec.rb`

**Interfaces:**
- Produces (fonctions de module, `morts` = tableau, index 0 = jour 1, `nil` = jour non saisi) :
  - `restant_veille(recu, morts, jour) → Integer`
  - `jours_en_alerte(recu, morts, seuil) → [Integer]` (jours N tels que `morts(N) ≥ seuil × restant_veille(N)`, restant > 0)
  - `dernier_jour_saisi(morts) → Integer` (0 si rien)
  - `mortalite_fenetre(recu, morts, fenetre) → Float` (% arrondi à 0,1 ; morts des `fenetre` derniers jours jusqu'au dernier saisi ÷ restant avant le premier de ces jours)

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dbs::CarnetMortalite do
  let(:recu) { 1000 }

  it 'calcule le restant de la veille en ignorant les jours non saisis' do
    expect(described_class.restant_veille(recu, [5, nil, 10], 3)).to eq 995
  end

  it 'alerte au seuil, égalité comprise, sur la base du restant de la veille' do
    morts = [10, 29, 30] # J3 : restant veille 961, 3 % = 28,83 → 30 alerte ; J2 : restant 990, 29,7 → 29 non
    expect(described_class.jours_en_alerte(recu, morts, 0.03)).to eq [3]
    expect(described_class.jours_en_alerte(100, [3], 0.03)).to eq [1]
  end

  it 'ne divise pas par zéro quand tout le lot est mort' do
    expect(described_class.jours_en_alerte(10, [10, 0], 0.03)).to eq [1]
    expect(described_class.mortalite_fenetre(10, [10, 0], 3)).to eq 100.0
  end

  it 'compte un jour à 0 mort comme une saisie, et saute les trous' do
    expect(described_class.dernier_jour_saisi([1, nil, 0])).to eq 3
    expect(described_class.dernier_jour_saisi([nil, nil])).to eq 0
  end

  it 'calcule la mortalité des 3 derniers jours saisis' do
    morts = [0, 0, 5, 5, 10] # fenêtre J3-J5 = 20 ; restant avant J3 = 1000
    expect(described_class.mortalite_fenetre(recu, morts, 3)).to eq 2.0
    expect(described_class.mortalite_fenetre(recu, [], 3)).to eq 0.0
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lib/dbs/carnet_mortalite_spec.rb`
Expected: FAIL (`uninitialized constant Dbs::CarnetMortalite`).

- [ ] **Step 3: Implement**

```ruby
# frozen_string_literal: true

module Dbs
  # Calculs du carnet de suivi des poussins, sans accès au dossier. `morts` : un élément par jour (index 0 = jour 1),
  # nil pour un jour non saisi (0 est une saisie). Base de l'alerte : l'effectif restant LA VEILLE (spec mère §5).
  module CarnetMortalite
    module_function

    def restant_veille(recu, morts, jour)
      recu - morts.first([jour - 1, 0].max).compact.sum
    end

    def jours_en_alerte(recu, morts, seuil)
      morts.each_with_index.filter_map do |mort, i|
        next if mort.nil?

        base = restant_veille(recu, morts, i + 1)
        i + 1 if base.positive? && mort >= seuil * base
      end
    end

    def dernier_jour_saisi(morts)
      (morts.rindex { |m| !m.nil? } || -1) + 1
    end

    def mortalite_fenetre(recu, morts, fenetre)
      dernier = dernier_jour_saisi(morts)
      return 0.0 if dernier.zero?

      debut = [dernier - fenetre + 1, 1].max
      base = restant_veille(recu, morts, debut)
      return 0.0 unless base.positive?

      (morts[(debut - 1)..(dernier - 1)].compact.sum * 100.0 / base).round(1)
    end
  end
end
```

- [ ] **Step 4: Run tests** — `bundle exec rspec spec/lib/dbs/carnet_mortalite_spec.rb` → PASS.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/lib/dbs/carnet_mortalite.rb spec/lib/dbs/carnet_mortalite_spec.rb
git add app/lib/dbs/carnet_mortalite.rb spec/lib/dbs/carnet_mortalite_spec.rb
git commit -m "feat(dbs): calculs du carnet de suivi (alerte, fenêtre, dernier jour saisi)"
```

---

### Task 3: plugin `dbs/suivi_carnet`

**Files:**
- Create: `app/lib/dbs/suivi_carnet.rb`
- Test: `spec/lib/dbs/suivi_carnet_spec.rb`

**Interfaces:**
- Consumes: `Dbs::CarnetMortalite` (Task 2) ; `SetAnnotationValue.set_value(dossier, instructeur_id, libelle, valeur)` ; `SendMessage.deliver_message(dossier, instructeur_id, texte)` ; `NotificationMailer.with(subject:, message:, recipients:).user_mail.deliver_later` ; `ScheduledTask.clear(task:, dossier:)` / `ScheduledTask.enqueue(numero, identifiant, params, run_at)`.
- Produces: tâche YAML `dbs/suivi_carnet`. Paramètres requis : `j0`, `recu`, `prefixe_jour` (« Morts du jour »), `alertes`, `relance`, `dernier_jour`, `mortalite`, `destinataires_alerte`, `objet_alerte`, `message_alerte`, `message_relance`. Optionnels : `seuil` (0.03), `fenetre` (3), `silence` (4), `nb_jours` (42), `heure_rejeu` (7), `prolongation_usager`, `prolongation_accordee`, `ecart_signale`, `destinataires_veterinaire`, `message_ecart`. Variables de message : `{jour}`, `{morts}`, `{restant}`, `{jours_a_saisir}`, `{saisi}`, `{accorde}` + champs du dossier. États par défaut `en_construction, en_instruction`. Identifiant planifié : `dbs/suivi_carnet/<n° de dossier>`.

- [ ] **Step 1: Write the failing test** — `spec/lib/dbs/suivi_carnet_spec.rb` :

```ruby
# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe Dbs::SuiviCarnet do
  include ActiveSupport::Testing::TimeHelpers

  let(:params) do
    { j0: 'Date de début d\'isolement (J0)', recu: 'Effectif reçu', prefixe_jour: 'Morts du jour',
      alertes: 'Alertes mortalité', relance: 'Relance silence', dernier_jour: 'Dernier jour saisi',
      mortalite: 'Mortalité sur 3 jours (%)', destinataires_alerte: 'cellule@exemple.pf',
      objet_alerte: 'Mortalité J{jour}', message_alerte: '{morts} morts / {restant}', message_relance: 'Saisir {jours_a_saisir}',
      nb_jours: 6, prolongation_usager: 'Durée de prolongation (jours)', prolongation_accordee: 'Prolongation totale (jours)',
      ecart_signale: 'Écart prolongation signalé', destinataires_veterinaire: 'veto@exemple.pf', message_ecart: '{saisi}/{accorde}' }
  end
  let(:task) { described_class.new(params) }
  let(:demarche) { instance_double(Demarche, instructeur: 'robot') }
  let(:morts) { [10, 30] }
  let(:trace) { { 'Alertes mortalité' => nil, 'Relance silence' => nil, 'Écart prolongation signalé' => nil,
                  'Prolongation totale (jours)' => nil } }
  let(:etat) { 'en_construction' }

  def int(label, v) = double(label, label:, __typename: 'IntegerNumberChamp', int_value: v, string_value: v.to_s)
  def txt(label, v) = double(label, label:, __typename: 'TextChamp', value: v, string_value: v)

  let(:dossier) do
    jours = (1..6).map { |n| int("Morts du jour #{n}", morts[n - 1]) }
    double('Carnet', number: 700_001, state: etat,
                     champs: [double('J0', label: "Date de début d'isolement (J0)", __typename: 'DateChamp', value: '2026-10-01',
                                           string_value: '2026-10-01', date: '2026-10-01'),
                              int('Effectif reçu', 1000), int('Durée de prolongation (jours)', nil), *jours],
                     annotations: trace.map { |k, v| k.include?('Prolongation') ? int(k, v) : txt(k, v) })
  end

  before do
    allow(SetAnnotationValue).to receive(:set_value).and_return(true)
    allow(SendMessage).to receive(:deliver_message).and_return(true)
    allow(NotificationMailer).to receive(:with).and_return(double('M', user_mail: double('D', deliver_later: true)))
    allow(ScheduledTask).to receive(:enqueue)
    allow(ScheduledTask).to receive(:clear)
    travel_to Time.zone.local(2026, 10, 3, 9, 0) # jour de suivi 2
  end

  after { travel_back }

  it 'alerte la cellule pour J2 (30 ≥ 3 % de 990) et trace le jour' do
    task.process(demarche, dossier)
    expect(NotificationMailer).to have_received(:with).with(hash_including(subject: 'Mortalité J2', recipients: 'cellule@exemple.pf'))
    expect(SetAnnotationValue).to have_received(:set_value).with(dossier, 'robot', 'Alertes mortalité', 'J2')
  end

  context 'J2 déjà signalé' do
    let(:trace) { super().merge('Alertes mortalité' => 'J2') }

    it 'ne réalerte pas' do
      task.process(demarche, dossier)
      expect(NotificationMailer).not_to have_received(:with).with(hash_including(subject: 'Mortalité J2'))
    end
  end

  it 'écrit le tableau de bord et replanifie au lendemain 7 h' do
    task.process(demarche, dossier)
    expect(SetAnnotationValue).to have_received(:set_value).with(dossier, 'robot', 'Dernier jour saisi', '2')
    expect(ScheduledTask).to have_received(:enqueue).with(700_001, 'dbs/suivi_carnet/700001', anything, Time.zone.local(2026, 10, 4, 7))
  end

  context 'silence de 4 jours' do
    let(:morts) { [1] }
    before { travel_to Time.zone.local(2026, 10, 6, 9, 0) } # jour 5, dernier saisi 1

    it 'relance l éleveur une fois par silence' do
      task.process(demarche, dossier)
      expect(SendMessage).to have_received(:deliver_message).with(dossier, 'robot', 'Saisir 2, 3, 4, 5')
      expect(SetAnnotationValue).to have_received(:set_value).with(dossier, 'robot', 'Relance silence', '1')
    end

    context 'déjà relancé pour ce silence' do
      let(:trace) { super().merge('Relance silence' => '1') }

      it 'ne relance pas' do
        task.process(demarche, dossier)
        expect(SendMessage).not_to have_received(:deliver_message)
      end
    end
  end

  context 'jour à 0 mort' do
    let(:morts) { [0, 0, 0, 0, 0] }
    before { travel_to Time.zone.local(2026, 10, 6, 9, 0) }

    it 'ne relance pas (0 est une saisie)' do
      task.process(demarche, dossier)
      expect(SendMessage).not_to have_received(:deliver_message)
    end
  end

  context 'écart de prolongation' do
    let(:trace) { super().merge('Prolongation totale (jours)' => 10) }

    it 'prévient la vétérinaire une fois par écart' do
      task.process(demarche, dossier)
      expect(NotificationMailer).to have_received(:with).with(hash_including(recipients: 'veto@exemple.pf', message: '0/10'))
      expect(SetAnnotationValue).to have_received(:set_value).with(dossier, 'robot', 'Écart prolongation signalé', '0/10')
    end
  end

  context 'carnet clos' do
    let(:etat) { 'accepte' }

    it 'n envoie rien et ne replanifie pas' do
      task.process(demarche, dossier)
      expect(NotificationMailer).not_to have_received(:with)
      expect(ScheduledTask).not_to have_received(:enqueue)
      expect(ScheduledTask).to have_received(:clear).with(task: 'dbs/suivi_carnet/700001', dossier: 700_001)
    end
  end
end
# rubocop:enable Metrics/BlockLength
```

- [ ] **Step 2: Run to verify failure** — `bundle exec rspec spec/lib/dbs/suivi_carnet_spec.rb` → FAIL (`uninitialized constant Dbs::SuiviCarnet`).

- [ ] **Step 3: Implement** — `app/lib/dbs/suivi_carnet.rb` :

```ruby
# frozen_string_literal: true

module Dbs
  # Surveillance quotidienne d'un carnet de suivi de poussins (spec carnet §5.2) : alerte de mortalité à la cellule
  # (une par jour signalé, trace « Alertes mortalité »), relance de l'éleveur après un silence (une par silence,
  # trace = dernier jour relancé), tableau de bord de la vétérinaire (dernier jour saisi, mortalité sur la fenêtre),
  # garde-fou de prolongation, et rejeu planifié le lendemain (un carnet silencieux n'est jamais modifié).
  class SuiviCarnet < FieldChecker
    ETATS_PAR_DEFAUT = %w[en_construction en_instruction].freeze
    DEFAUTS = { seuil: 0.03, fenetre: 3, silence: 4, nb_jours: 42, heure_rejeu: 7 }.freeze

    def version
      super + 1
    end

    def required_fields
      super + %i[j0 recu prefixe_jour alertes relance dernier_jour mortalite destinataires_alerte objet_alerte
                 message_alerte message_relance]
    end

    def authorized_fields
      super + DEFAUTS.keys + %i[prolongation_usager prolongation_accordee ecart_signale destinataires_veterinaire message_ecart]
    end

    def initialize(params)
      super
      @states = Set.new(ETATS_PAR_DEFAUT) if @params[:etat_du_dossier].blank?
      @cfg = DEFAUTS.merge(@params.to_h.symbolize_keys.slice(*DEFAUTS.keys))
    end

    def process(demarche, dossier)
      super
      unless must_check?(dossier)
        ScheduledTask.clear(task: identifiant, dossier: dossier.number)
        return
      end

      j0 = date_champ(@params[:j0])
      recu = entier(@params[:recu])
      return if j0.nil? || recu.nil?

      jour = (Time.zone.today - j0).to_i
      morts = (1..@cfg[:nb_jours].to_i).map { |n| entier("#{@params[:prefixe_jour]} #{n}") }
      alerter(recu, morts)
      relancer(jour, morts)
      tableau_de_bord(recu, morts)
      garde_fou_prolongation
      replanifier
    end

    private

    def identifiant = "dbs/suivi_carnet/#{@dossier.number}"

    def alerter(recu, morts)
      deja = texte(@params[:alertes]).scan(/J(\d+)/).flatten.map(&:to_i)
      nouveaux = CarnetMortalite.jours_en_alerte(recu, morts, @cfg[:seuil].to_f) - deja
      return if nouveaux.empty?

      nouveaux.each do |n|
        variables = { jour: n, morts: morts[n - 1], restant: CarnetMortalite.restant_veille(recu, morts, n) }
        courriel(@params[:destinataires_alerte], @params[:objet_alerte], @params[:message_alerte], variables)
      end
      ecrire(@params[:alertes], (deja + nouveaux).sort.map { |n| "J#{n}" }.join(', '))
    end

    def relancer(jour, morts)
      dernier = CarnetMortalite.dernier_jour_saisi(morts)
      return if jour - dernier < @cfg[:silence].to_i || texte(@params[:relance]) == dernier.to_s

      a_saisir = ((dernier + 1)..[jour, morts.size].min).to_a.join(', ')
      SendMessage.deliver_message(@dossier, instructeur_id, instanciate(@params[:message_relance], { jours_a_saisir: a_saisir }))
      ecrire(@params[:relance], dernier.to_s)
    end

    def tableau_de_bord(recu, morts)
      ecrire(@params[:dernier_jour], CarnetMortalite.dernier_jour_saisi(morts).to_s)
      ecrire(@params[:mortalite], CarnetMortalite.mortalite_fenetre(recu, morts, @cfg[:fenetre].to_i).to_s)
    end

    def garde_fou_prolongation
      return if @params[:prolongation_accordee].blank?

      saisi = entier(@params[:prolongation_usager]).to_i
      accorde = entier(@params[:prolongation_accordee]).to_i
      paire = "#{saisi}/#{accorde}"
      return if saisi == accorde || texte(@params[:ecart_signale]) == paire

      courriel(@params[:destinataires_veterinaire], "Carnet #{@dossier.number} : prolongation à vérifier",
               @params[:message_ecart], { saisi:, accorde: })
      ecrire(@params[:ecart_signale], paire)
    end

    def replanifier
      demain = Time.zone.tomorrow.in_time_zone.change(hour: @cfg[:heure_rejeu].to_i)
      ScheduledTask.clear(task: identifiant, dossier: @dossier.number)
      ScheduledTask.enqueue(@dossier.number, identifiant, @params.except(:scheduled), demain)
    end

    def courriel(destinataires, objet, message, variables)
      NotificationMailer.with(subject: instanciate(objet, variables), message: instanciate(message, variables),
                              recipients: destinataires).user_mail.deliver_later
    end

    def ecrire(libelle, valeur)
      return if libelle.blank?

      dossier_updated(@dossier) if SetAnnotationValue.set_value(@dossier, instructeur_id, libelle, valeur)
    end

    def champ(libelle) = object_field_values(@dossier, libelle, log_empty: false).first

    def entier(libelle)
      c = champ(libelle)
      c.respond_to?(:int_value) ? c.int_value : nil
    end

    def texte(libelle) = champ(libelle)&.string_value.to_s

    def date_champ(libelle)
      valeur = champ_value(champ(libelle))
      valeur.is_a?(Date) ? valeur : Date.parse(valeur.to_s)
    rescue Date::Error
      nil
    end
  end
end
```

Si les tests révèlent que `instanciate` ne remplace pas les variables du hash (signature `instanciate(template, source)`), passer par `Payzen::StringTemplate` comme `daf/message`, ou formater avec `template.gsub(/\{(\w+)\}/) { variables[$1.to_sym] }` avant `instanciate` — consigner la décision (Ruling).

- [ ] **Step 4: Run tests** — `bundle exec rspec spec/lib/dbs/` → PASS.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/lib/dbs/suivi_carnet.rb spec/lib/dbs/suivi_carnet_spec.rb
git add app/lib/dbs/suivi_carnet.rb spec/lib/dbs/suivi_carnet_spec.rb
git commit -m "feat(dbs): suivi_carnet — alerte mortalité, relance silence, tableau de bord, rejeu quotidien"
```

---

### Task 4: démarche carnet et annotation 3899 (MCP)

**Files:** aucun fichier du dépôt ; révisions brouillon par le MCP `mes-demarches`.

**Interfaces:**
- Consumes: **l'utilisateur crée d'abord une démarche vide** (coquille, personne morale non requise : personne physique) et en donne le numéro — **arrêt obligatoire** avant ce point.
- Produces: stable_ids des champs préremplis (n° d'engagement, élevage, éleveur, effectif attribué, J0) pour le `prerempli` de Task 6, et le chemin `/commencer/<uuid>` de la démarche (relevé dans l'admin par l'utilisateur).

- [ ] **Step 1: Champs publics** (`mcp__mes-demarches__ajouter_champ`, ordre exact ; insérer N champs « après » une même ancre en ordre inverse) :
  1. section « Lot reçu » ; « Numéro du dossier d'engagement » (dossier_link, obligatoire) ; « Nom de l'élevage » (text) ; « Nom de l'éleveur » (text) ; « Effectif attribué » (integer_number) ; « Date de début d'isolement (J0) » (date, obligatoire) ; « Effectif reçu » (integer_number, obligatoire, description « Nombre de poussins effectivement reçus ; corrigez si des poussins sont morts pendant le transport. »).
  2. section « Suivi quotidien » (explication : « Chaque jour, indiquez le nombre de poussins morts, même 0, puis cliquez sur Déposer les modifications. ») ; « Jour de suivi » (formule `AUJOURDHUI() - {Date de début d'isolement (J0)}`) ; « Durée de prolongation (jours) » (integer_number, 0-21, description de la spec) ; « Durée d'isolement » (formule `21 + {Durée de prolongation (jours)}`).
  3. « Morts du jour 1 » … « Morts du jour 42 » (integer_number, ≥ 0, obligatoires).
  4. « Total des morts » (formule `SOMME({Morts du jour 1}, …, {Morts du jour 42})`), « Effectif restant » (formule `{Effectif reçu} - {Total des morts}`).
- [ ] **Step 2: Conditions** (`mcp__mes-demarches__definir_condition`) : jour N ≤ 21 → `[{ Jour de suivi, superieur_ou_egal, N }]` ; jour N ≥ 22 → combinateur `ET`, `[{ Jour de suivi ≥ N }, { Durée d'isolement ≥ N }]`.
- [ ] **Step 3: Annotations** (`prive: true`, ordre) : section « Tableau de bord » — « Jour de suivi (agent) » (formule, même expression), « Dernier jour saisi » (text), « Mortalité sur 3 jours (%) » (text), « Mortalité totale (%) » (formule `ARRONDI({Total des morts} * 100 / {Effectif reçu}, 1)`) ; section « Suivi robot » — « Alertes mortalité », « Relance silence », « Écart prolongation signalé » (text) ; section « Visite » — « Date de visite » (date), « Agents », « Vaccins et traitements », « Niveau d'activité », « Alimentation », « Présence de signes cliniques », « Autre » (textarea), « Décision » (drop_down : Levée / Prolongation / Abattage), « Prolongation totale (jours) » (integer 0-21, condition Décision = Prolongation), « Prochaine visite » (date, idem), « Date d'abattage » (date, condition Décision = Abattage), « Motif de l'abattage » (textarea, idem), « Visa de la vétérinaire » (visa, habilités du visa 3899), « Suite administrative délivrée » (pièce jointe).
- [ ] **Step 4: 3899** : annotation texte « Carnets envoyés » (description « Renseigné automatiquement : une ligne par éleveur invité à tenir son carnet. Ne pas modifier. »), après « Invitations envoyées » (197057).
- [ ] **Step 5: Vérifier** la révision (lecture `MesDemarches::Queries::DemarcheRevision`) et la formule « Total des morts » ≤ 1 000 caractères ; consigner les stable_ids dans la spec (§4) et commiter la spec.

---

### Task 5: gabarit « Suite administrative »

**Files:**
- Create: `storage/models/dbs/poussins/Suite administrative.docx` (non versionné), script de construction dans le scratchpad.

**Interfaces:**
- Consumes: colonnes de Task 6 — `dossier`, `engagement`, `eleveur`, `elevage`, `effectif_recu`, `total_morts`, `restant`, `date_visite`, `agents`, `date_abattage`, `motif`, `est_abattage` (booléen) ; calculées : `aujourd_hui`, `visa_de_la_veterinaire_prenom|nom|fonction`, `dernier_instructeur_prenom|nom`.

- [ ] **Step 1: Construire** à partir de `storage/models/dbs/poussins/Certificat d'isolement.docx` (en-tête, cadre de titre, tableau de signature avec tampon et « Cachet » déjà au point) : titre « SUITE ADMINISTRATIVE » ; N° « «=dossier» / MPR / DBS / ZOO » ; références « Certificat d'isolement n° «=engagement»/MPR/DBS/ZOO » ; « Au vu du contrôle effectué le «=date_visite» par «=agents» » ; tableau élevage / éleveur / effectif reçu / morts / restant ; décision conditionnelle Sablon : `«est_abattage:if»Abattage du lot le «=date_abattage» — motif : «=motif»«est_abattage:endIf»«est_abattage:unless»Levée de l'isolement des poussins mis en isolement par le certificat susvisé.«est_abattage:endUnless»` (paragraphes de contrôle séparés) ; signataire `visa_de_la_veterinaire_*`.
- [ ] **Step 2: Contrôler** : liste des `MERGEFIELD` = interface ci-dessus ; rendu de test (levée et abattage) via Sablon + `soffice`, aucun champ brut, une page.
- [ ] **Step 3: Faire retoucher** dans Word par l'utilisateur (sa version devient la référence ; retirer `w:proofErr` puis recontrôler).

---

### Task 6: YAML, contrôle de bout en bout, livraison

**Files:**
- Modify: `storage/configurations/dbs_poussins.yml`

- [ ] **Step 1: LP (3899)** — dans `dbs_poussins_laissez_passer.when_ok`, ajouter :

```yaml
    - dbs/inviter_eleveurs:                     # invitations aux CARNETS (LP accepté ; engagements tardifs au passage suivant)
        etat_du_dossier: [ accepte ]
        seulement_engages: Engagements reçus
        demarche_cible: <uuid carnet relevé à Task 4>
        invitations_envoyees: Carnets envoyés
        eleveurs: Liste des élevages destinataires
        importateur_eleveur: *dbs_poussins_importateur_eleveur
        objet: "Poussins d'un jour — votre carnet de suivi"
        message: *invitation_carnet
        prerempli:
          <id n° d'engagement>: Numéro d'engagement
          <id élevage>: Nom de l'élevage
          <id éleveur>: Nom et Prénom de l'éleveur
          <id effectif attribué>: Quantité de poussins
          <id J0>: date_traitement
```

avec l'ancre de message `invitation_carnet` (lien `{lien}`, consigne : déposer le carnet dès réception — accusé de réception —, puis chaque jour « Déposer les modifications »).

- [ ] **Step 2: Bloc carnet** `dbs_poussins_carnet` (`demarches: [<n° carnet>]`, `<<: *dbs_poussins_par_defaut`) — `when_ok` :

```yaml
    - dbs/suivi_carnet:
        j0: Date de début d'isolement (J0)
        recu: Effectif reçu
        prefixe_jour: Morts du jour
        alertes: Alertes mortalité
        relance: Relance silence
        dernier_jour: Dernier jour saisi
        mortalite: Mortalité sur 3 jours (%)
        prolongation_usager: Durée de prolongation (jours)
        prolongation_accordee: Prolongation totale (jours)
        ecart_signale: Écart prolongation signalé
        destinataires_alerte: clautier@idt.pf           # staging ; production : cellule zoosanitaire
        destinataires_veterinaire: clautier@idt.pf
        objet_alerte: "Mortalité anormale — carnet {number}, jour {jour}"
        message_alerte: "Carnet {number} ({Nom de l'élevage}) : {morts} morts au jour {jour}, effectif restant la veille {restant}."
        message_relance: "Bonjour, il manque le nombre de poussins morts pour les jours {jours_a_saisir}. Saisissez-les (0 s'il n'y a eu aucun mort) puis cliquez sur « Déposer les modifications »."
        message_ecart: "La durée de prolongation saisie par l'éleveur ({saisi} jours) diffère du total accordé ({accorde} jours)."
    - conditional_field:
        etat_du_dossier: [ en_construction, en_instruction ]
        champ: Visa de la vétérinaire
        valeurs:
          "":
          par défaut:
            - conditional_field:
                champ: Décision
                valeurs:
                  Prolongation:
                    - daf/message:
                        message: *message_prolongation       # compte rendu complet + « indiquez {Prolongation totale (jours)} … »
                    - set_field:
                        champ: Visa de la vétérinaire
                        valeur: ""
                  Levée:
                    - publipostage_v3: *dbs_poussins_suite_administrative
                    - conditional_field:
                        champ: Suite administrative délivrée
                        valeurs: { "": , par défaut: [ { dossier_accepter: } ] }
                  Abattage:
                    - publipostage_v3: *dbs_poussins_suite_administrative
                    - conditional_field:
                        champ: Suite administrative délivrée
                        valeurs:
                          "":
                          par défaut:
                            - dossier_refuser:
                                motivation: "Abattage du lot ordonné par la Direction de la biosécurité : voir la suite administrative jointe au dossier."
```

`*message_prolongation` : « Visite du {Date de visite} par {Agents}. Vaccins et traitements : {Vaccins et traitements}. Niveau d'activité : … Alimentation : … Signes cliniques : … Autre : … Décision : prolongation de l'isolement, {Prolongation totale (jours)} jours en tout ; prochaine visite le {Prochaine visite}. Indiquez {Prolongation totale (jours)} dans « Durée de prolongation (jours) » de votre carnet. » ; `*dbs_poussins_suite_administrative` : publipostage v3 (`champ_cible: Suite administrative délivrée`, `calculs: calculs/email_to_names` avec `*dbs_poussins_agents`, colonnes de Task 5 dont `est_abattage` sur `Décision` — à défaut d'égalité, deux ancres `levée`/`abattage` avec un champ booléen calculé ; consigner le choix).

- [ ] **Step 3: Instancier** toutes les tâches et sous-tâches (y compris imbriquées) : aucune erreur.
- [ ] **Step 4: Bout en bout** sur un carnet de test (créé par l'utilisateur via le lien reçu) : rejouer `dbs/suivi_carnet` sans envoi (doubles ou `deliver_later` intercepté) et le rendu de l'acte (levée, abattage) ; PDF sans champ brut.
- [ ] **Step 5: Livrer** : specs `spec/lib/dbs spec/lib/calculs` vertes, `rubocop --parallel` propre ; fusion dans `dev` (worktree), specs `spec/lib spec/jobs` vertes, push ; **attendre CI verte + robot de staging redéployé** ; puis `mc cp` du gabarit et du YAML (copies dans `deployment/`) ; contrôle etag du YAML. Mettre à jour spec et mémoire.
