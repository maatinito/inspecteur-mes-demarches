# Cascade d'invitation des éleveurs (poussins DBS) — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Quand l'agent coche « Envoyer les engagements » sur un laissez-passer (démarche 3899), chaque éleveur de la liste reçoit un courriel avec un lien prérempli vers la démarche engagement (4038) ; quand un éleveur dépose son engagement, le laissez-passer reçoit la liste des engagements reçus et celle des engagements manquants ; un agent qui oublie de cocher est relancé.

**Architecture:** Deux nouvelles tâches `InspectorTask` (`Dbs::InviterEleveurs` sur la 3899, `Dbs::EngagementRecu` sur la 4038) branchées par un fichier de configuration `dbs_poussins.yml`, un constructeur d'URL de préremplissage réutilisable (`PrefillURL`), et un module pur de format/parsing des deux zones de texte (`Dbs::ListeEngagements`). La trace des envois et le lien engagement → laissez-passer vivent dans des annotations privées de Mes-Démarches, jamais dans Grist. La relance de l'agent réutilise `dead_line_checker` sous un `conditional_field`.

**Tech Stack:** Ruby on Rails, GraphQL Mes-Démarches (`MesDemarches`, `DossierActions`, `SetAnnotationValue`), `NotificationMailer#user_mail`, RSpec avec doubles (style B de `spec/lib/set_annotation_spec.rb`), configuration YAML chargée par `VerificationService`.

**Spec:** `docs/superpowers/specs/2026-08-18-dbs-import-poussins-design.md` — §3.1 (3899), §3.2 (4038, mécanique « Engagements reçus »), §5 (déclencheur n° 1, trace, relance agent), §11 (identifiants des champs).

## Global Constraints

- **Source de vérité = Mes-Démarches.** Aucune tâche de ce plan ne lit Grist ou Baserow (décision 17 de la spec, mémoire `feedback_source_verite_mes_demarches`).
- **Le robot réécrit les zones de texte en entier** à chaque passage, à partir de la liste complète ; il n'ajoute jamais une ligne à l'aveugle (spec §3.2).
- **Format des lignes fixe, écrit et relu par le robot** : « Engagements reçus » = `Nom (courriel) — dossier N — déposé le JJ/MM/AAAA[ — non attendu]` ; « Engagements manquants » = `Nom au téléphone (courriel)` ; « Invitations envoyées » = `courriel — envoyé le JJ/MM/AAAA HH:MM`. Le tiret est le **tiret cadratin « — » (U+2014)**, entouré d'espaces.
- **Rapprochement par courriel**, comparé en minuscules (spec §4).
- **Aucun horaire d'ouverture codé** (décision 23) — sans objet ici mais à respecter dans les messages.
- **Identifiants de champs (révision brouillon, stables à la publication)** : 3899 → bloc « Liste des éleveurs » 132719 (enfants : « Nom et Prénom de l'éleveur » 132721, « Nom de l'élevage » 196207, « Email de l'éleveur » 181893, « Téléphone de l'éleveur » 196213, « Quantité de poussins » 132723), case « Envoyer les engagements » 196946, annotations « Engagements reçus » 196270, « Engagements manquants » 196271, « Invitations envoyées » 197057, « Alertes délai » 197058, « Date et heure d'atterrissage du vol » 107912, « Numéro de vol » 132710. 4038 → « Numéro du dossier de laissez-passer » 197027, « Importateur du lot » 197029, « Date d'arrivée prévue du lot » 197031, « Numéro du vol d'arrivée » 197033, « Effectif attribué à votre élevage » 197035, « Nom et prénom de l'éleveur » 197038, « Téléphone » 197047.
- **Préremplissage par URL** : `<MES_DEMARCHES_URL>/commencer/<chemin>?champ_<Base64("Champ-<stable_id>")>=<valeur>` ; une date part en ISO 8601 `AAAA-MM-JJ`.
- **Compte robot** : `email_instructeur: robot-mes-demarches@administration.gov.pf` ; ce compte doit être instructeur des **deux** démarches (il écrit des annotations sur la 3899 depuis un dossier de la 4038).
- **Avant chaque commit** : `bundle exec rubocop -A` puis `bundle exec rake lint` (CLAUDE.md). Travailler sur la branche `dev`, ne jamais pousser sur `master`.
- **Configuration non versionnée** : `storage/configurations/dbs_poussins.yml` est ignoré par git ; la copie de déploiement va dans `deployment/robot-mes-demarches-staging/configurations/dbs_poussins.yml` (l'utilisateur lance `mirror_staging.sh`).

---

## Structure des fichiers

| Fichier | Rôle |
|---|---|
| `app/lib/prefill_url.rb` (créer) | Construit l'URL de préremplissage d'une démarche à partir de `{stable_id => valeur}`. Pur, sans réseau. Réutilisé plus tard pour le carnet. |
| `app/lib/dbs/liste_engagements.rb` (créer) | Format et parsing des lignes des deux zones « Engagements reçus » / « Engagements manquants ». Pur. |
| `app/lib/dbs/inviter_eleveurs.rb` (créer) | Tâche sur la 3899 : lit le bloc éleveurs, envoie un courriel par éleveur non encore invité, trace dans « Invitations envoyées ». |
| `app/lib/dbs/engagement_recu.rb` (créer) | Tâche sur la 4038 : au dépôt d'un engagement, réécrit les deux zones du laissez-passer lié. |
| `spec/lib/prefill_url_spec.rb`, `spec/lib/dbs/liste_engagements_spec.rb`, `spec/lib/dbs/inviter_eleveurs_spec.rb`, `spec/lib/dbs/engagement_recu_spec.rb` (créer) | Tests unitaires, doubles RSpec, aucun réseau. |
| `storage/configurations/dbs_poussins.yml` (créer, non versionné) + copie `deployment/robot-mes-demarches-staging/configurations/dbs_poussins.yml` | Deux points d'entrée (3899, 4038), messages, relance agent. |
| `docs/CONFIGURATION_GUIDE.md` (modifier, section « Patterns courants ») | Documenter les deux tâches et le pattern « invitation préremplie ». |

Le module `Dbs` n'existe pas encore : Zeitwerk le crée automatiquement à partir du dossier `app/lib/dbs/` (comme `app/lib/daf/` → `Daf`). Aucun fichier `dbs.rb` à écrire.

---

### Task 1: `PrefillURL` — URL de préremplissage

**Files:**
- Create: `app/lib/prefill_url.rb`
- Test: `spec/lib/prefill_url_spec.rb`

**Interfaces:**
- Produces: `PrefillURL.build(chemin, valeurs)` → `String` ; `chemin` = segment après `/commencer/` ; `valeurs` = `Hash{Integer|String => Object}` (stable_id → valeur). `PrefillURL.champ_id(stable_id)` → `String` Base64.
- Consumes: `MesDemarches.public_url` (existant, `app/lib/mes_demarches.rb:30-32`), `DateValue < Date` (`app/lib/date_value.rb`), `DatetimeValue < DateTime` (`app/lib/datetime_value.rb`).

- [ ] **Step 1: Écrire le test qui échoue**

```ruby
# spec/lib/prefill_url_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PrefillURL do
  before { allow(MesDemarches).to receive(:public_url).and_return('https://www.mes-demarches.gov.pf') }

  it 'encode chaque champ en champ_<Base64(Champ-<stable_id>)>=<valeur>' do
    url = described_class.build('engagements-poussins', { 197_027 => 654_125, 197_038 => 'Manutere TERE' })
    expect(url).to eq 'https://www.mes-demarches.gov.pf/commencer/engagements-poussins' \
                      '?champ_Q2hhbXAtMTk3MDI3=654125&champ_Q2hhbXAtMTk3MDM4=Manutere+TERE'
  end

  it 'formate les dates et dates-heures en ISO 8601 (jour seul)' do
    url = described_class.build('p', { 1 => DateValue.new(2026, 9, 30), 2 => DatetimeValue.new(2026, 10, 1, 1, 30) })
    expect(url).to include('=2026-09-30', '=2026-10-01')
  end

  it 'ignore les valeurs nulles ou vides et encode le padding Base64 de la clé' do
    url = described_class.build('p', { 1 => nil, 2 => '  ', 65_381 => 12 })
    expect(url).to eq 'https://www.mes-demarches.gov.pf/commencer/p?champ_Q2hhbXAtNjUzODE%3D=12'
  end

  it 'joint un tableau de valeurs par une virgule' do
    expect(described_class.build('p', { 1 => %w[Ponte Chair] })).to end_with('=Ponte%2C+Chair')
  end
end
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

Run: `bundle exec rspec spec/lib/prefill_url_spec.rb`
Expected: FAIL — `uninitialized constant PrefillURL`

- [ ] **Step 3: Écrire l'implémentation minimale**

```ruby
# app/lib/prefill_url.rb
# frozen_string_literal: true

require 'base64'
require 'cgi'

# URL de préremplissage d'une démarche Mes-Démarches :
#   <MES_DEMARCHES_URL>/commencer/<chemin>?champ_<id>=<valeur>&…
# où <id> est l'identifiant GraphQL du descripteur de champ, Base64("Champ-<stable_id>").
# Les dates partent en ISO 8601 (AAAA-MM-JJ), seul format accepté par la plateforme.
# La clé est aussi échappée : un stable_id court produit un Base64 avec « = » de padding.
class PrefillURL
  def self.build(chemin, valeurs)
    query = valeurs.filter_map do |stable_id, valeur|
      texte = format_value(valeur)
      next if texte.blank?

      "champ_#{CGI.escape(champ_id(stable_id))}=#{CGI.escape(texte)}"
    end
    "#{MesDemarches.public_url}/commencer/#{chemin}?#{query.join('&')}"
  end

  def self.champ_id(stable_id)
    Base64.strict_encode64("Champ-#{stable_id}")
  end

  def self.format_value(valeur)
    case valeur
    when nil then nil
    when Date, DateTime, Time then valeur.to_date.iso8601
    when Array then valeur.map { |v| format_value(v) }.compact.join(', ')
    else valeur.to_s.strip
    end
  end
end
```

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

Run: `bundle exec rspec spec/lib/prefill_url_spec.rb`
Expected: 4 examples, 0 failures

- [ ] **Step 5: Rubocop, lint, commit**

```bash
bundle exec rubocop -A app/lib/prefill_url.rb spec/lib/prefill_url_spec.rb && bundle exec rake lint
git add app/lib/prefill_url.rb spec/lib/prefill_url_spec.rb
git commit -m "feat(prefill): construire l'URL de préremplissage d'une démarche

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `Dbs::ListeEngagements` — format et parsing des deux zones

**Files:**
- Create: `app/lib/dbs/liste_engagements.rb`
- Test: `spec/lib/dbs/liste_engagements_spec.rb`

**Interfaces:**
- Produces:
  - `Dbs::ListeEngagements::Engagement` = `Struct(nom:, email:, numero:, date:, attendu:)` (`email` en minuscules, `numero` Integer, `date` Date, `attendu` Boolean).
  - `Dbs::ListeEngagements.parse_recus(texte) → Array<Engagement>` (lignes non conformes ignorées).
  - `Dbs::ListeEngagements.format_recus(engagements) → String` (triées par numéro).
  - `Dbs::ListeEngagements.upsert(engagements, nouveau) → Array<Engagement>` (remplace l'entrée de même numéro).
  - `Dbs::ListeEngagements.format_manquants(eleveurs, engagements) → String` où `eleveurs = Array<Hash{nom:, email:, telephone:}>`.

- [ ] **Step 1: Écrire le test qui échoue**

```ruby
# spec/lib/dbs/liste_engagements_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dbs::ListeEngagements do
  let(:tere) do
    described_class::Engagement.new(nom: 'Manutere TERE', email: 'manutere@exemple.pf', numero: 654_125,
                                    date: Date.new(2026, 9, 1), attendu: true)
  end
  let(:hoa) do
    described_class::Engagement.new(nom: 'Vaimiti HOA', email: 'vaimiti@exemple.pf', numero: 655_888,
                                    date: Date.new(2026, 9, 15), attendu: false)
  end

  describe '.format_recus / .parse_recus' do
    let(:texte) do
      "Manutere TERE (manutere@exemple.pf) — dossier 654125 — déposé le 01/09/2026\n" \
        'Vaimiti HOA (vaimiti@exemple.pf) — dossier 655888 — déposé le 15/09/2026 — non attendu'
    end

    it 'écrit une ligne par engagement, triée par numéro, avec la mention « non attendu »' do
      expect(described_class.format_recus([hoa, tere])).to eq texte
    end

    it 'relit exactement ce qu il a écrit' do
      expect(described_class.parse_recus(texte)).to eq [tere, hoa]
    end

    it 'ignore les lignes vides ou modifiées à la main et normalise le courriel en minuscules' do
      texte_sale = "\n#{texte.lines.first}  \nune note de l'agent\nJean (JEAN@Ex.PF) — dossier 1 — déposé le 02/02/2026\n"
      expect(described_class.parse_recus(texte_sale).map(&:email)).to eq ['manutere@exemple.pf', 'jean@ex.pf']
    end
  end

  describe '.upsert' do
    it 'remplace l engagement de même numéro et garde les autres' do
      tere2 = tere.dup.tap { |e| e.date = Date.new(2026, 9, 2) }
      expect(described_class.upsert([tere, hoa], tere2)).to contain_exactly(hoa, tere2)
    end
  end

  describe '.format_manquants' do
    let(:eleveurs) do
      [{ nom: 'Manutere TERE', email: 'Manutere@exemple.pf', telephone: '87 54 65 75' },
       { nom: 'Tehani MOU', email: 'tehani@exemple.pf', telephone: '' },
       { nom: 'Vaimiti HOA', email: 'vaimiti@exemple.pf', telephone: '88 65 25 62' }]
    end

    it 'liste les éleveurs sans engagement, avec leur téléphone, rapprochés par courriel sans la casse' do
      expect(described_class.format_manquants(eleveurs, [tere])).to eq(
        "Tehani MOU (tehani@exemple.pf)\nVaimiti HOA au 88 65 25 62 (vaimiti@exemple.pf)"
      )
    end

    it 'rend une chaîne vide quand tout le monde a signé' do
      expect(described_class.format_manquants(eleveurs, [tere, hoa, hoa.dup.tap { |e| e.email = 'tehani@exemple.pf' }])).to eq ''
    end
  end
end
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

Run: `bundle exec rspec spec/lib/dbs/liste_engagements_spec.rb`
Expected: FAIL — `uninitialized constant Dbs`

- [ ] **Step 3: Écrire l'implémentation**

```ruby
# app/lib/dbs/liste_engagements.rb
# frozen_string_literal: true

module Dbs
  # Les deux zones de texte du laissez-passer que le robot réécrit en entier :
  # « Engagements reçus » et « Engagements manquants ». Le format des lignes est
  # fixe : le robot l'écrit ET le relit, l'agent ne fait que lire. Une ligne
  # retouchée à la main ne correspond plus au format et disparaît à la
  # réécriture suivante — c'est voulu, la source est la liste complète.
  class ListeEngagements
    Engagement = Struct.new(:nom, :email, :numero, :date, :attendu, keyword_init: true)

    TIRET = ' — '
    NON_ATTENDU = 'non attendu'
    LIGNE_RECU = /\A(?<nom>.+?) \((?<email>[^)]+)\)#{TIRET}dossier (?<numero>\d+)#{TIRET}déposé le (?<date>\d{2}\/\d{2}\/\d{4})(?<suffixe>#{TIRET}#{NON_ATTENDU})?\z/

    def self.parse_recus(texte)
      texte.to_s.lines.map(&:strip).reject(&:blank?).filter_map do |ligne|
        m = LIGNE_RECU.match(ligne)
        next unless m

        Engagement.new(nom: m[:nom], email: m[:email].downcase, numero: m[:numero].to_i,
                       date: Date.strptime(m[:date], '%d/%m/%Y'), attendu: m[:suffixe].nil?)
      end
    end

    def self.format_recus(engagements)
      engagements.sort_by(&:numero).map do |e|
        ligne = "#{e.nom} (#{e.email})#{TIRET}dossier #{e.numero}#{TIRET}déposé le #{e.date.strftime('%d/%m/%Y')}"
        e.attendu ? ligne : "#{ligne}#{TIRET}#{NON_ATTENDU}"
      end.join("\n")
    end

    def self.upsert(engagements, nouveau)
      engagements.reject { |e| e.numero == nouveau.numero } + [nouveau]
    end

    # eleveurs : lignes du bloc « Liste des éleveurs » du laissez-passer,
    # sous la forme [{ nom:, email:, telephone: }].
    def self.format_manquants(eleveurs, engagements)
      recus = engagements.map { |e| e.email.downcase }.to_set
      eleveurs.reject { |e| recus.include?(e[:email].to_s.downcase) }.map do |e|
        [e[:nom], e[:telephone].presence && "au #{e[:telephone]}", "(#{e[:email]})"].compact.join(' ')
      end.join("\n")
    end
  end
end
```

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

Run: `bundle exec rspec spec/lib/dbs/liste_engagements_spec.rb`
Expected: 6 examples, 0 failures

- [ ] **Step 5: Rubocop, lint, commit**

```bash
bundle exec rubocop -A app/lib/dbs/liste_engagements.rb spec/lib/dbs/liste_engagements_spec.rb && bundle exec rake lint
git add app/lib/dbs/liste_engagements.rb spec/lib/dbs/liste_engagements_spec.rb
git commit -m "feat(dbs): format et parsing des zones « Engagements reçus / manquants »

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: `Dbs::InviterEleveurs` — envoi des liens d'engagement

**Files:**
- Create: `app/lib/dbs/inviter_eleveurs.rb`
- Test: `spec/lib/dbs/inviter_eleveurs_spec.rb`

**Interfaces:**
- Consumes: `PrefillURL.build(chemin, valeurs)` (Task 1) ; `FieldChecker` (`app/lib/field_checker.rb`) : `process(demarche, dossier)` + `super`, `must_check?`, `param_field(:clé)&.rows`, `annotation(nom, warn_if_empty:)`, `select_champ(champs, label)`, `champs_to_values(champs)`, `object_field_values(source, chemin, log_empty:)`, `instanciate(template, hash)`, `instructeur_id`, `dossier_updated` ; `SetAnnotationValue.set_value(dossier, instructeur_id, nom_annotation, texte)` ; `NotificationMailer.with(subject:, message:, recipients:).user_mail.deliver_later`.
- Produces: tâche YAML `dbs/inviter_eleveurs` avec les clés `demarche_engagement` (chemin `/commencer/…`), `champ_eleveurs`, `annotation_envois`, `objet`, `message`, `prerempli` (Hash `stable_id: chemin_de_champ`), optionnelles `champ_email`, `champ_nom`, `etat_du_dossier` (défaut `en_instruction`). Variables disponibles dans `objet`/`message` : `{lien}`, `{nom_eleveur}`, plus tout champ du dossier (`{number}`, `{demandeur.entreprise.raison_sociale}`, …). Ligne tracée : `courriel — envoyé le JJ/MM/AAAA HH:MM`.

- [ ] **Step 1: Écrire le test qui échoue**

```ruby
# spec/lib/dbs/inviter_eleveurs_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dbs::InviterEleveurs do
  let(:task) do
    described_class.new(
      demarche_engagement: 'engagements-poussins',
      champ_eleveurs: 'Liste des éleveurs',
      annotation_envois: 'Invitations envoyées',
      objet: 'Engagement poussins — {nom_eleveur}',
      message: "Bonjour {nom_eleveur}, lot {number} : {lien}",
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
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

Run: `bundle exec rspec spec/lib/dbs/inviter_eleveurs_spec.rb`
Expected: FAIL — `uninitialized constant Dbs::InviterEleveurs`

- [ ] **Step 3: Écrire l'implémentation**

```ruby
# app/lib/dbs/inviter_eleveurs.rb
# frozen_string_literal: true

module Dbs
  # Déclencheur n° 1 de la cascade poussins (spec §5) : pour chaque ligne du bloc
  # « Liste des éleveurs » du laissez-passer, envoie à l'éleveur un courriel
  # avec un lien prérempli vers la démarche engagement. La trace des envois est
  # l'annotation texte « Invitations envoyées » du laissez-passer, une ligne
  # « courriel — envoyé le JJ/MM/AAAA HH:MM » par éleveur : un éleveur déjà
  # présent n'est pas réinvité, un éleveur ajouté après coup l'est au passage
  # suivant. À brancher sous un conditional_field sur la case
  # « Envoyer les engagements ».
  #
  # prerempli : { stable_id (démarche engagement) => chemin de champ }, le chemin
  # est cherché d'abord dans la ligne du bloc (champs de l'éleveur), puis dans le
  # dossier (« number », « demandeur.entreprise.raison_sociale », libellé d'un champ).
  class InviterEleveurs < FieldChecker
    LIGNE_ENVOI = /\A(?<email>\S+) — envoyé le (?<date>.+)\z/
    ETATS_PAR_DEFAUT = %w[en_instruction].freeze

    def version
      super + 1
    end

    def required_fields
      super + %i[demarche_engagement champ_eleveurs annotation_envois objet message prerempli]
    end

    def authorized_fields
      super + %i[champ_email champ_nom]
    end

    def initialize(params)
      super
      @states = Set.new(ETATS_PAR_DEFAUT) if @params[:etat_du_dossier].blank?
      @champ_email = @params[:champ_email] || "Email de l'éleveur"
      @champ_nom = @params[:champ_nom] || "Nom et Prénom de l'éleveur"
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      rows = param_field(:champ_eleveurs)&.rows || []
      lignes = lignes_envois
      deja = lignes.filter_map { |l| LIGNE_ENVOI.match(l)&.[](:email)&.downcase }.to_set
      nouvelles = rows.filter_map { |row| inviter(row, deja) }
      return if nouvelles.empty?

      SetAnnotationValue.set_value(dossier, instructeur_id, @params[:annotation_envois], (lignes + nouvelles).join("\n"))
      dossier_updated(dossier)
    end

    private

    def lignes_envois
      annotation(@params[:annotation_envois], warn_if_empty: false)&.value.to_s.lines.map(&:strip).reject(&:blank?)
    end

    def inviter(row, deja)
      email = valeur(row, @champ_email).downcase
      return nil if email.blank? || deja.include?(email)

      variables = { lien: PrefillURL.build(@params[:demarche_engagement], valeurs_prerempli(row)), nom_eleveur: valeur(row, @champ_nom) }
      NotificationMailer.with(subject: instanciate(@params[:objet], variables),
                              message: instanciate(@params[:message], variables),
                              recipients: email).user_mail.deliver_later
      Rails.logger.info("Invitation à signer l'engagement envoyée à #{email}")
      "#{email} — envoyé le #{Time.zone.now.strftime('%d/%m/%Y %H:%M')}"
    end

    def valeur(row, label)
      champs_to_values(select_champ(row.champs, label)).first.to_s.strip
    end

    def valeurs_prerempli(row)
      @params[:prerempli].to_h do |stable_id, chemin|
        champs = object_field_values(row, chemin.to_s, log_empty: false)
        champs = object_field_values(@dossier, chemin.to_s, log_empty: false) if champs.blank?
        [stable_id, champs_to_values(champs).first]
      end
    end
  end
end
```

Notes pour l'implémenteur :
- `object_field_values(row, …)` marche parce qu'une ligne de bloc répétable GraphQL répond à `champs` (voir `FieldChecker#object_field_values`, `app/lib/field_checker.rb:224-241`) ; `number` et `demandeur.entreprise.raison_sociale` ne sont pas trouvés sur la ligne, d'où le repli sur `@dossier`.
- `instanciate(template, hash)` : les clés du Hash (`lien`, `nom_eleveur`) ont priorité, les autres `{…}` se résolvent sur le dossier (`FieldChecker#get_values_of`, `app/lib/field_checker.rb:387-401`).
- Un `EmailChamp` réel tombe dans le `else` de `graphql_champ_value` et lit `string_value` avec un avertissement dans les logs ; c'est le comportement existant, on ne touche pas à `FieldChecker` ici.

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

Run: `bundle exec rspec spec/lib/dbs/inviter_eleveurs_spec.rb`
Expected: 4 examples, 0 failures

- [ ] **Step 5: Rubocop, lint, commit**

```bash
bundle exec rubocop -A app/lib/dbs/inviter_eleveurs.rb spec/lib/dbs/inviter_eleveurs_spec.rb && bundle exec rake lint
git add app/lib/dbs/inviter_eleveurs.rb spec/lib/dbs/inviter_eleveurs_spec.rb
git commit -m "feat(dbs): inviter les éleveurs à signer leur engagement par lien prérempli

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: `Dbs::EngagementRecu` — réécrire les deux zones du laissez-passer

**Files:**
- Create: `app/lib/dbs/engagement_recu.rb`
- Test: `spec/lib/dbs/engagement_recu_spec.rb`

**Interfaces:**
- Consumes: `Dbs::ListeEngagements.{parse_recus, upsert, format_recus, format_manquants}` et `Dbs::ListeEngagements::Engagement` (Task 2) ; `DossierActions.on_dossier(numero) → dossier | nil` (`app/lib/dossier_actions.rb:32-39`) ; `SetAnnotationValue.get_annotation(dossier, nom)` et `.set_value(...)` ; `FieldChecker#field`, `#dossier_field(dossier, nom, warn_if_empty:)`, `#champ_value`, `#select_champ`, `#champs_to_values`, `#instructeur_id`.
- Produces: tâche YAML `dbs/engagement_recu` avec les clés `champ_laissez_passer`, `champ_eleveurs`, `annotation_recus`, `annotation_manquants`, optionnelles `champ_nom` (engagement), `champ_nom_eleveur`, `champ_email_eleveur`, `champ_tel_eleveur` (bloc du laissez-passer), `etat_du_dossier` (défaut `en_construction, en_instruction, accepte`).

- [ ] **Step 1: Écrire le test qui échoue**

```ruby
# spec/lib/dbs/engagement_recu_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dbs::EngagementRecu do
  let(:task) do
    described_class.new(
      champ_laissez_passer: 'Numéro du dossier de laissez-passer',
      champ_eleveurs: 'Liste des éleveurs',
      annotation_recus: 'Engagements reçus',
      annotation_manquants: 'Engagements manquants'
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

  let(:recus) { champ('Engagements reçus', recus_texte, typename: 'TextareaChamp') }
  let(:manquants) { champ('Engagements manquants', '', typename: 'TextareaChamp') }
  let(:recus_texte) { '' }
  let(:laissez_passer) do
    double('LaissezPasser', number: 654_000,
                            champs: [double('Bloc', label: 'Liste des éleveurs', __typename: 'RepetitionChamp',
                                                    rows: [row('Manutere TERE', 'manutere@exemple.pf', '87 54 65 75'),
                                                           row('Vaimiti HOA', 'vaimiti@exemple.pf', '88 65 25 62')])],
                            annotations: [recus, manquants])
  end
  let(:lien) { champ('Numéro du dossier de laissez-passer', '654000', typename: 'DossierLinkChamp') }
  let(:engagement) do
    double('Engagement', number: 655_888, state: 'en_construction', date_depot: '2026-09-15T08:12:00+00:00',
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

  it 'ne fait rien sur un dossier refusé' do
    allow(engagement).to receive(:state).and_return('refuse')
    task.process(demarche, engagement)
    expect(DossierActions).not_to have_received(:on_dossier)
  end
end
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

Run: `bundle exec rspec spec/lib/dbs/engagement_recu_spec.rb`
Expected: FAIL — `uninitialized constant Dbs::EngagementRecu`

- [ ] **Step 3: Écrire l'implémentation**

```ruby
# app/lib/dbs/engagement_recu.rb
# frozen_string_literal: true

module Dbs
  # Au dépôt d'un engagement d'éleveur (démarche 4038), inscrit cet engagement
  # dans le laissez-passer qu'il désigne (démarche 3899) : la zone
  # « Engagements reçus » est réécrite en entier avec l'engagement ajouté, la
  # zone « Engagements manquants » avec les éleveurs du bloc qui n'ont pas
  # encore signé (rapprochement par courriel du compte, en minuscules).
  #
  # C'est ainsi que le laissez-passer connaît ses engagements : l'API GraphQL
  # ne filtre pas les dossiers par valeur de champ, le lien inverse se construit
  # à l'écriture (spec §3.2, décision 17). Écrire dans le laissez-passer le fait
  # repasser en inspection, ce qui servira au visa (tranche suivante).
  class EngagementRecu < FieldChecker
    ETATS_PAR_DEFAUT = %w[en_construction en_instruction accepte].freeze

    def version
      super + 1
    end

    def required_fields
      super + %i[champ_laissez_passer champ_eleveurs annotation_recus annotation_manquants]
    end

    def authorized_fields
      super + %i[champ_nom champ_nom_eleveur champ_email_eleveur champ_tel_eleveur]
    end

    def initialize(params)
      super
      @states = Set.new(ETATS_PAR_DEFAUT) if @params[:etat_du_dossier].blank?
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      numero = field(@params[:champ_laissez_passer])&.string_value.to_s[/\d+/]
      if numero.blank?
        Rails.logger.warn("Engagement #{dossier.number} : aucun laissez-passer lié, rien à faire")
        return
      end

      laissez_passer = DossierActions.on_dossier(numero.to_i)
      raise "Laissez-passer #{numero} introuvable depuis l'engagement #{dossier.number}" if laissez_passer.nil?

      eleveurs = eleveurs_du_lot(laissez_passer)
      engagements = ListeEngagements.upsert(ListeEngagements.parse_recus(texte_annotation(laissez_passer, :annotation_recus)),
                                            engagement_courant(eleveurs))
      ecrire(laissez_passer, :annotation_recus, ListeEngagements.format_recus(engagements))
      ecrire(laissez_passer, :annotation_manquants, ListeEngagements.format_manquants(eleveurs, engagements))
    end

    private

    def engagement_courant(eleveurs)
      email = @dossier.usager.email.to_s.strip.downcase
      ListeEngagements::Engagement.new(nom: nom_eleveur, email:, numero: @dossier.number,
                                       date: Date.parse(@dossier.date_depot),
                                       attendu: eleveurs.any? { |e| e[:email] == email })
    end

    def nom_eleveur
      nom = champ_value(field(@params[:champ_nom] || "Nom et prénom de l'éleveur", warn_if_empty: false)).to_s.strip
      return nom if nom.present?

      demandeur = @dossier.demandeur
      demandeur.respond_to?(:entreprise) ? demandeur.entreprise&.raison_sociale.to_s : ''
    end

    def eleveurs_du_lot(laissez_passer)
      rows = dossier_field(laissez_passer, @params[:champ_eleveurs], warn_if_empty: false)&.rows || []
      rows.map do |row|
        { nom: valeur(row, @params[:champ_nom_eleveur] || "Nom et Prénom de l'éleveur"),
          email: valeur(row, @params[:champ_email_eleveur] || "Email de l'éleveur").downcase,
          telephone: valeur(row, @params[:champ_tel_eleveur] || "Téléphone de l'éleveur") }
      end
    end

    def valeur(row, label)
      champs_to_values(select_champ(row.champs, label)).first.to_s.strip
    end

    def texte_annotation(laissez_passer, cle)
      SetAnnotationValue.get_annotation(laissez_passer, @params[cle])&.value.to_s
    end

    def ecrire(laissez_passer, cle, texte)
      SetAnnotationValue.set_value(laissez_passer, instructeur_id, @params[cle], texte)
    end
  end
end
```

Notes pour l'implémenteur :
- La tâche n'appelle **pas** `dossier_updated` : c'est le laissez-passer qui est modifié, pas le dossier courant ; le laissez-passer repassera de lui-même en inspection (sa `dateDerniereModification` change).
- `instructeur_id` renvoie `demarche.instructeur`, l'identifiant GraphQL du compte robot résolu sur la 4038 ; la mutation d'annotation sur la 3899 n'est acceptée que si ce compte est aussi instructeur de la 3899 (contrainte globale).
- `SetAnnotationValue.set_value` ne réécrit pas une valeur identique (`app/lib/set_annotation_value.rb:4-15`) : rejouer la tâche est sans effet.

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

Run: `bundle exec rspec spec/lib/dbs/engagement_recu_spec.rb`
Expected: 5 examples, 0 failures

- [ ] **Step 5: Lancer toute la suite dbs + rubocop, lint, commit**

```bash
bundle exec rspec spec/lib/dbs spec/lib/prefill_url_spec.rb
bundle exec rubocop -A app/lib/dbs/engagement_recu.rb spec/lib/dbs/engagement_recu_spec.rb && bundle exec rake lint
git add app/lib/dbs/engagement_recu.rb spec/lib/dbs/engagement_recu_spec.rb
git commit -m "feat(dbs): inscrire chaque engagement déposé dans son laissez-passer

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Configuration `dbs_poussins.yml` et relance de l'agent

**Files:**
- Create: `storage/configurations/dbs_poussins.yml` (non versionné)
- Create (copie identique): `deployment/robot-mes-demarches-staging/configurations/dbs_poussins.yml`

**Interfaces:**
- Consumes: clés YAML des tâches `dbs/inviter_eleveurs` (Task 3) et `dbs/engagement_recu` (Task 4) ; `conditional_field` (`app/lib/conditional_field.rb`, une `CheckboxChamp` cochée vaut `Oui`, décochée `Non`, clé `par défaut`) ; `dead_line_checker` (`app/lib/dead_line_checker.rb`, phase `instruction: { duree_max:, seuils: [{ jours:, alerter: [..], objet:, message: }] }`, `annotation_alertes`, variables `{duree_effective}` `{jours_restants}` `{duree_max}`).
- Produces: deux points d'entrée `dbs_poussins_laissez_passer` (3899) et `dbs_poussins_engagement` (4038).

- [ ] **Step 1: Relever le chemin `/commencer/…` de la démarche 4038**

Dans l'administration Mes-Démarches de la 4038, onglet Présentation, copier le segment de l'URL « Commencer la démarche » (par exemple `engagements-pour-recevoir-des-poussins-d-un-jour`). Il n'est pas exposé par l'API (`Demarche` GraphQL n'a pas de champ `path`). Le reporter dans `demarche_engagement` ci-dessous.

- [ ] **Step 2: Écrire le fichier de configuration**

```yaml
# storage/configurations/dbs_poussins.yml
#------------------------------------------------------------------------------------------------------------
#  DBS — importation de poussins d'un jour
#  3899 : demande de laissez-passer (importateur) — 4038 : engagement de l'éleveur destinataire
#  Spec : docs/superpowers/specs/2026-08-18-dbs-import-poussins-design.md (§3.1, §3.2, §5)
#------------------------------------------------------------------------------------------------------------

dbs_poussins_par_defaut: &dbs_poussins_par_defaut
  email_instructeur: robot-mes-demarches@administration.gov.pf
  messages_automatiques: false
  pieces_messages:
    debut_premier_mail: "Bonjour<br>Un contrôle automatique a été fait sur le dossier."
    debut_second_mail: "Bonjour<br>Une nouvelle vérification automatique a été faite."
    entete_anomalies: "Les points suivants sur le dossier doivent être résolus pour que le dossier puisse être traité :"
    entete_anomalie: "Il n'y a qu'un seul point à résoudre pour que le dossier puisse être traité :"
    tout_va_bien: "Toutes les vérifications automatiques se sont bien passées et un agent va prendre la suite de votre dossier."
    fin_anomalie: |
      <b>Important</b> : ne donnez pas de corrections via la messagerie.
      Effectuez les corrections en <b>modifiant directement le dossier</b>.<br>
      Si vous avez des difficultés à résoudre ces points, n'hésitez pas à répondre à ce message et nous pourrons vous aider.
    fin_mail: "Cordialement.<br>La cellule zoosanitaire de la Direction de la biosécurité"

dbs_poussins_messages:
  invitation_engagement: &invitation_engagement |
    Bonjour {nom_eleveur},

    {demandeur.entreprise.raison_sociale} a déclaré à la Direction de la biosécurité un lot de poussins d'un jour dont une partie vous est destinée (dossier n° {number}, arrivée prévue le {Date et heure d'atterrissage du vol}).

    Avant l'arrivée des poussins, vous devez signer votre engagement d'éleveur destinataire sur Mes-Démarches. Le formulaire est déjà prérempli : il vous reste à indiquer le lieu d'isolement et à cocher les sept engagements.

    Signer mon engagement : {lien}

    Ce lien est personnel. Si vous n'êtes pas concerné par ce lot, ignorez ce message.

    La cellule zoosanitaire de la Direction de la biosécurité — 40 540 100 — zoo.dbs@biosecurite.gov.pf
  relance_agent_envoi: &relance_agent_envoi |
    Bonjour,
    Le dossier de laissez-passer n° {number} ({demandeur.entreprise.raison_sociale}) est en instruction depuis {duree_effective} jours et la case « Envoyer les engagements » n'est pas cochée : aucun éleveur n'a encore été invité à signer son engagement.
    Dossier : https://www.mes-demarches.gov.pf/procedures/3899/dossiers/{number}
    Le robot Mes-Démarches

dbs_poussins_inviter: &dbs_poussins_inviter
  etat_du_dossier: en_instruction
  demarche_engagement: engagements-pour-recevoir-des-poussins-d-un-jour   # segment relevé à l'étape 1
  champ_eleveurs: Liste des éleveurs
  champ_email: Email de l'éleveur
  champ_nom: Nom et Prénom de l'éleveur
  annotation_envois: Invitations envoyées
  objet: "Poussins d'un jour — signez votre engagement d'éleveur destinataire"
  message: *invitation_engagement
  prerempli:
    197027: number                                  # Numéro du dossier de laissez-passer (lien dossier)
    197029: demandeur.entreprise.raison_sociale     # Importateur du lot
    197031: Date et heure d'atterrissage du vol     # Date d'arrivée prévue du lot (jour seul)
    197033: Numéro de vol                           # Numéro du vol d'arrivée (libellé 3899 : « Numéro de vol »)
    197035: Quantité de poussins                    # Effectif attribué à votre élevage (ligne du bloc)
    197038: Nom et Prénom de l'éleveur              # Nom et prénom de l'éleveur (ligne du bloc)
    197047: Téléphone de l'éleveur                  # Téléphone (ligne du bloc)

dbs_poussins_relance_envoi: &dbs_poussins_relance_envoi
  annotation_alertes: Alertes délai
  instruction:
    duree_max: 2
    seuils:
      - jours: 0
        alerter: [ clautier@idt.pf ]               # staging ; en production : adresse de la cellule zoosanitaire
        objet: "Laissez-passer {number} : engagements non envoyés"
        message: *relance_agent_envoi

dbs_poussins_laissez_passer:
  <<: *dbs_poussins_par_defaut
  demarches: [ 3899 ]
  controles:
  when_ok:
    - conditional_field:
        etat_du_dossier: en_instruction
        champ: Envoyer les engagements
        valeurs:
          Oui:
            - dbs/inviter_eleveurs: *dbs_poussins_inviter
          par défaut:
            - dead_line_checker: *dbs_poussins_relance_envoi

dbs_poussins_engagement:
  <<: *dbs_poussins_par_defaut
  demarches: [ 4038 ]
  controles:
  when_ok:
    - dbs/engagement_recu:
        etat_du_dossier: [ en_construction, en_instruction, accepte ]
        champ_laissez_passer: Numéro du dossier de laissez-passer
        champ_nom: Nom et prénom de l'éleveur
        champ_eleveurs: Liste des éleveurs
        champ_nom_eleveur: Nom et Prénom de l'éleveur
        champ_email_eleveur: Email de l'éleveur
        champ_tel_eleveur: Téléphone de l'éleveur
        annotation_recus: Engagements reçus
        annotation_manquants: Engagements manquants
```

Pourquoi ces choix :
- La relance agent utilise `dead_line_checker` en phase `instruction` avec `duree_max: 2` et un seuil à `0` jour restant : l'alerte part quand le dossier a passé 2 jours en instruction (jours calendaires, `compute_instruction_days` somme les intervalles `en_instruction` des `traitements`), une seule fois grâce à `annotation_alertes`. Écart assumé avec la spec qui disait « 2 jours ouvrés » : le compteur existant ne connaît pas les jours ouvrés, et une relance le lundi pour un dossier passé en instruction le vendredi est acceptable.
- Le `conditional_field` porte `etat_du_dossier: en_instruction` : ni la case ni la relance n'ont de sens en construction, et un dossier refusé n'envoie rien (décision 4 révisée).
- `controles:` vide, comme sur `dbs-zoo-lp` : le bloc n'a que des tâches `when_ok`.

- [ ] **Step 3: Valider la syntaxe YAML et l'instanciation des tâches**

```bash
ruby -ryaml -e "YAML.load_file('storage/configurations/dbs_poussins.yml', aliases: true); puts 'YAML ok'"
timeout 120 bin/rails runner '
data = YAML.load_file("storage/configurations/dbs_poussins.yml", aliases: true)
VerificationService.procedures(data).each do |name, procedure|
  tasks = InspectorTask.create_tasks(procedure["when_ok"])
  invalid = tasks.reject(&:valid?)
  puts "#{name}: #{tasks.size} tâche(s) when_ok, erreurs : #{invalid.map(&:errors).flatten.inspect}"
end'
```
Expected : `YAML ok`, puis deux lignes avec `erreurs : []`. Une erreur `n'existe(nt) pas sur dbs/inviter_eleveurs` signale une clé YAML absente de `authorized_fields`/`required_fields` : corriger le YAML, pas la tâche.

- [ ] **Step 4: Copier dans le dépôt de déploiement staging**

```bash
cp storage/configurations/dbs_poussins.yml deployment/robot-mes-demarches-staging/configurations/dbs_poussins.yml
cd deployment/robot-mes-demarches-staging && git status --short configurations/dbs_poussins.yml && cd -
```
Le commit dans ce dépôt et `mirror_staging.sh` sont faits par l'utilisateur (mémoire `feedback_deploiement_prod_staging`).

---

### Task 6: Test de bout en bout sur dossiers de test

**Files:** aucun fichier de code ; ce sont des manipulations sur Mes-Démarches et une lecture des logs du robot staging.

**Prérequis** : la configuration est déployée sur staging (Task 5) ; le compte `robot-mes-demarches@administration.gov.pf` est instructeur des démarches 3899 et 4038 ; l'exécutant dispose de deux adresses de courriel qu'il peut lire (une pour l'importateur, une pour l'« éleveur »).

- [ ] **Step 1: Déposer un laissez-passer de test sur la 3899**

Depuis le lien « tester la démarche » de la 3899 (mode test, dossiers visibles par l'API), déposer un dossier avec : raison sociale, date et heure d'atterrissage, numéro de vol, « Les poussins repartent-ils vers une île ? » = non, et **deux lignes** dans « Liste des éleveurs » — l'une avec l'adresse « éleveur » lisible par l'exécutant, l'autre avec une adresse fictive du domaine `exemple.pf`. Noter le numéro du dossier `N_LP`.

- [ ] **Step 2: Passer en instruction sans cocher la case**

En tant qu'instructeur, passer `N_LP` en instruction. Attendre un passage du robot (staging : cron du `VerificationService`). Vérifier dans les logs staging : `Executing 'par défaut' tasks as Envoyer les engagements : 'Non'` et aucune ligne `Invitation à signer l'engagement envoyée`. Vérifier que « Invitations envoyées » est vide.

- [ ] **Step 3: Cocher « Envoyer les engagements »**

Cocher la case dans les annotations de `N_LP`, enregistrer. Après le passage suivant du robot :
- logs : deux lignes `Invitation à signer l'engagement envoyée à …` ;
- annotation « Invitations envoyées » : deux lignes `courriel — envoyé le JJ/MM/AAAA HH:MM` ;
- la boîte « éleveur » a reçu le courriel, dont le lien commence par `https://www.mes-demarches.gov.pf/commencer/` et contient `champ_Q2hhbXAtMTk3MDI3=N_LP`.

- [ ] **Step 4: Vérifier l'idempotence**

Modifier une annotation anodine de `N_LP` (carnet de notes) pour le faire repasser en inspection. Après le passage : aucune nouvelle ligne dans « Invitations envoyées », aucun nouveau courriel.

- [ ] **Step 5: Déposer l'engagement depuis le lien**

Ouvrir le lien du courriel, connecté avec le compte « éleveur ». Vérifier que les champs « Lot de poussins concerné », le nom et le téléphone sont préremplis (la date en `AAAA-MM-JJ` doit apparaître comme une date valide dans le champ date). Compléter lieu d'isolement, commune, les sept cases, déposer. Noter `N_ENG`.

- [ ] **Step 6: Vérifier les deux zones du laissez-passer**

Après le passage du robot sur la 4038, ouvrir `N_LP` :
- « Engagements reçus » = `Nom (courriel-éleveur) — dossier N_ENG — déposé le JJ/MM/AAAA` ;
- « Engagements manquants » = la ligne de l'adresse fictive, `Nom au téléphone (adresse@exemple.pf)`.
Logs 4038 : pas d'erreur `Laissez-passer … introuvable`.

- [ ] **Step 7: Ajouter un éleveur après coup**

Sur `N_LP`, l'importateur (ou l'agent via « repasser en construction » puis en instruction) ajoute une troisième ligne d'éleveurs avec une adresse lisible. Au passage suivant : une seule nouvelle ligne dans « Invitations envoyées », un seul courriel ; « Engagements manquants » compte maintenant deux lignes.

- [ ] **Step 8: Vérifier la relance agent**

Sur un second dossier de test `N_LP2` passé en instruction sans cocher la case : au bout de deux jours, l'adresse `alerter` reçoit « Laissez-passer N_LP2 : engagements non envoyés » et « Alertes délai » contient `0`. Ce point ne se vérifie qu'en laissant le dossier vieillir ; le noter dans le compte rendu de recette s'il n'a pas pu être observé.

- [ ] **Step 8 bis: Points ajoutés par la revue finale**

- Sur `N_LP` (case cochée à J0), vérifier à J+2 qu'**aucune** relance « engagements non envoyés » ne part : la
  tâche `dead_line_checker` de la branche `Oui` doit avoir annulé la planification.
- Vérifier que la plateforme accepte réellement le préremplissage du champ **lien dossier** (197027) et de la
  **date** (197031, valeur `AAAA-MM-JJ` sur un champ date).
- Faire signer un engagement avec un **compte dont le courriel n'est pas** celui saisi par l'importateur :
  attendu « non attendu » dans les reçus ET la ligne toujours dans les manquants — montrer ce cas au service.
- Vérifier le rendu de `{Date et heure d'atterrissage du vol}` dans le courriel (format français) et que le
  lien « Signer mon engagement » est cliquable.

- [ ] **Step 9: Consigner le résultat**

Ajouter au §11.6 de la spec une ligne « Recette cascade du JJ/MM : … » avec les numéros `N_LP`, `N_ENG`, ce qui a été observé et ce qui reste à observer (relance agent), puis commit de la spec :

```bash
git add docs/superpowers/specs/2026-08-18-dbs-import-poussins-design.md
git commit -m "docs(poussins): compte rendu de recette de la cascade d'engagements

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Documenter les deux tâches dans le guide de configuration

**Files:**
- Modify: `docs/CONFIGURATION_GUIDE.md` — ajouter une sous-section `### 8. Invitation préremplie vers une autre démarche (dbs/inviter_eleveurs, dbs/engagement_recu)` à la fin de la section « Patterns courants » (après `### 7. Génération d'identifiant unique sécurisé`, avant `## Exemples commentés`).

- [ ] **Step 1: Ajouter la sous-section**

```markdown
### 8. Invitation préremplie vers une autre démarche

Cas d'usage : un dossier « parent » (ex. laissez-passer) liste des personnes qui doivent déposer chacune un
dossier « enfant » dans une autre démarche (ex. engagement d'éleveur). Le robot les invite par courriel avec
un lien prérempli, puis, quand un enfant est déposé, l'inscrit dans le parent.

**Pourquoi une annotation et pas Grist** : l'API GraphQL ne filtre pas les dossiers par valeur de champ ; le
parent ne peut pas retrouver ses enfants. Le lien se construit donc à l'écriture, dans une annotation texte du
parent, source de vérité unique (voir `docs/superpowers/specs/2026-08-18-dbs-import-poussins-design.md`, §3.2).

```yaml
# Côté parent : sous un conditional_field sur une case cochée par l'agent
- dbs/inviter_eleveurs:
    etat_du_dossier: en_instruction
    demarche_engagement: chemin-de-la-demarche-enfant     # segment après /commencer/
    champ_eleveurs: Liste des éleveurs                      # bloc répétable du parent
    champ_email: Email de l'éleveur                         # sous-champ courriel (défaut)
    champ_nom: Nom et Prénom de l'éleveur                   # sous-champ nom (défaut)
    annotation_envois: Invitations envoyées                 # annotation texte : « courriel — envoyé le … »
    objet: "Signez votre engagement"
    message: "Bonjour {nom_eleveur}, lot {number} : {lien}"  # {lien} et {nom_eleveur} sont fournis par la tâche
    prerempli:                                              # stable_id du champ ENFANT : chemin dans le PARENT
      197027: number                                        # cherché dans la ligne du bloc, puis dans le dossier
      197038: Nom et Prénom de l'éleveur
      197031: Date et heure d'atterrissage du vol           # une date part en AAAA-MM-JJ

# Côté enfant : au dépôt, réécrit deux annotations du parent
- dbs/engagement_recu:
    etat_du_dossier: [ en_construction, en_instruction, accepte ]
    champ_laissez_passer: Numéro du dossier de laissez-passer   # champ lien dossier vers le parent
    champ_eleveurs: Liste des éleveurs                          # bloc du parent
    annotation_recus: Engagements reçus                         # « Nom (courriel) — dossier N — déposé le … »
    annotation_manquants: Engagements manquants                 # « Nom au téléphone (courriel) »
```

Règles : le robot réécrit les zones en entier à chaque passage (pas de doublon, pas de dérive si l'agent a
touché au texte) ; le rapprochement se fait par courriel en minuscules ; un enfant dont le courriel n'est pas
dans le bloc est listé avec « — non attendu ». Les identifiants de champs se relèvent avec `bin/describe_demarche`
ou l'outil MCP `lire_demarche` ; ils sont stables à la publication.
```

- [ ] **Step 2: Vérifier la table des matières du guide**

Si la section « Table des matières » (ligne 5) liste les patterns numérotés, y ajouter l'entrée « 8. Invitation préremplie vers une autre démarche ». Sinon, ne rien faire.

- [ ] **Step 3: Commit**

```bash
git add docs/CONFIGURATION_GUIDE.md
git commit -m "docs(guide): pattern d'invitation préremplie vers une autre démarche

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Auto-revue du plan

**Couverture de la spec (périmètre cascade)** : déclencheur n° 1 « case cochée, dossier en instruction » → Task 5 (`conditional_field`) + Task 3 ; lien prérempli (n° LP, importateur, date, vol, effectif, nom, téléphone) → Tasks 1, 3, 5 ; trace non rejouable et réinvitation d'un éleveur ajouté → Task 3 ; « Engagements reçus » / « manquants » réécrits en entier, format fixe, rapprochement courriel, « non attendu » → Tasks 2, 4 ; relance agent après 2 jours → Task 5 ; test de bout en bout → Task 6 ; documentation → Task 7. Hors périmètre volontaire, tranche suivante : visa, « Laissez-passer visé le » sur les engagements, certificats, carnet, courriel d'annulation si refus après envoi.

**Types et noms** : `PrefillURL.build(chemin, valeurs)` identique en Tasks 1, 3 ; `Dbs::ListeEngagements::Engagement(nom:, email:, numero:, date:, attendu:)` identique en Tasks 2, 4 ; `format_manquants(eleveurs, engagements)` avec `eleveurs = [{nom:, email:, telephone:}]` identique en Tasks 2, 4 ; clés YAML des Tasks 3 et 4 reprises telles quelles en Task 5 et Task 7.

**Placeholders** : le seul élément à relever par l'exécutant est le chemin `/commencer/` de la 4038 (Task 5, étape 1), qui n'existe pas dans l'API ; l'adresse `alerter` de staging est celle de l'utilisateur, à remplacer par celle de la cellule en production.
