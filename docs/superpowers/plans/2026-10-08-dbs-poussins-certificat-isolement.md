# Certificat d'isolement (poussins) — plan de mise en œuvre

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** à la validation d'un engagement d'éleveur (visa de l'agent sur la démarche 4038), le robot génère le certificat d'isolement dans l'engagement puis accepte le dossier ; le laissez-passer (3899) ne cite plus que les certificats réellement délivrés.

**Architecture:** une chaîne YAML côté engagement (visa → `publipostage_v3` → acceptation), calquée sur celle du laissez-passer. Les données du lot se lisent dans la demande de laissez-passer liée par **chemins pointés** (`object_field_values` traverse le champ lien de dossier) ; deux formules d'annotation sur la 3899 fournissent ce qui demande un calcul (pays d'origine, date de la demande). Code Ruby : un suffixe « certificat délivré le J » dans les lignes d'engagement (`Dbs::ListeEngagements`, `Dbs::EngagementRecu`, `Dbs::ReferencesLaissezPasser`) et un calcul générique `calculs/te_fenua` pour lire la parcelle du champ carte.

**Tech Stack:** Ruby 3.4 / Rails, RSpec, gem Sablon (publipostage v3), MCP `mes-demarches` (modification des démarches brouillon), `mc` (S3 staging), LibreOffice (`soffice`) pour les rendus de contrôle.

**Spec:** `docs/superpowers/specs/2026-10-08-dbs-poussins-certificat-isolement-design.md` (et, pour le contexte, `docs/superpowers/specs/2026-08-18-dbs-import-poussins-design.md` §12).

## Global Constraints

- Branche de travail : `dbs-poussins-cascade` ; livrer sur `dev` par fusion (worktree, `.env` lié), **jamais** sur `master`.
- Avant chaque commit Ruby : `bundle exec rubocop -A <fichiers>` puis aucune offense ; specs vertes.
- Configuration : `storage/configurations/dbs_poussins.yml` (non versionnée), chargée avec `YAML.load_file(..., aliases: true)` ; copie dans `deployment/robot-mes-demarches-staging/configurations/`.
- Gabarits Word : publiés **depuis `storage/models/`** par `mc cp` (jamais depuis `deployment/`, que SharePoint réécrit) ; contrôle avant publication = liste des `MERGEFIELD` + rendu de bout en bout sans aucun champ brut `«…»` dans le PDF.
- En publipostage, une colonne `champs:` **ne voit pas** les sorties de `calculs:` (exécutés après) : le gabarit lit les clés calculées sous leur nom `parameterize(separator: '_')`.
- Libellés exacts (4038) : « Numéro du dossier de laissez-passer » (DossierLink 197027), « Nom et prénom de l'éleveur » (197038), « Effectif attribué à votre élevage » (197035), « Date d'arrivée prévue du lot » (197031), « Numéro du vol d'arrivée » (197033), « Importateur du lot » (197029), « Adresse du lieu d'isolement » (Te Fenua 197045), « Courriel d'attribution » (197081).
- Adresse du robot (visas) : `robot-mes-demarches@administration.gov.pf` ; habilités du visa 3899 : `clautier@idt.pf`, `timeri.galenon@administration.gov.pf`, `severine.sampietro@administration.gov.pf`.
- Textes utilisateur en français, point médian pour l'inclusif (« le·la vétérinaire »).

## Review Focus

- Engagement **accepté à la main sans certificat** : la ligne du laissez-passer ne doit PAS dire « certificat délivré » (test Task 2).
- **Anciennes lignes** d'« Engagements reçus » sans suffixe : relues sans perte, et la référence 6/ les ignore (tests Tasks 1 et 3).
- Champ Te Fenua **vide, sans marqueur ou JSON invalide** : le calcul rend des chaînes vides, sans lever (test Task 4).
- Laissez-passer **visé avant tout certificat** : référence 6/ absente, pas de ligne vide ni d'erreur Sablon (test Task 3, liste vide).
- Engagement **non attendu** et accepté : le suffixe « certificat délivré » suit « non attendu » dans le bon ordre et se relit (test Task 1).

---

### Task 1: `Dbs::ListeEngagements` — suffixe « certificat délivré le J »

**Files:**
- Modify: `app/lib/dbs/liste_engagements.rb`
- Test: `spec/lib/dbs/liste_engagements_spec.rb`

**Interfaces:**
- Produces: `Dbs::ListeEngagements::Engagement` gagne le membre `delivre_le` (`Date` ou `nil`) ; `format_recus` écrit `" — certificat délivré le JJ/MM/AAAA"` après l'éventuel `" — non attendu"` ; `parse_recus` le relit (`nil` si absent).

- [ ] **Step 1: Write the failing tests** — ajouter dans `describe '.format_recus / .parse_recus'` :

```ruby
    it 'écrit et relit la date de délivrance du certificat, après « non attendu »' do
      delivre = described_class::Engagement.new(nom: 'Vaimiti HOA', email: 'vaimiti@exemple.pf', numero: 655_888,
                                                date: Date.new(2026, 9, 15), attendu: false,
                                                delivre_le: Date.new(2026, 10, 7))
      ligne = described_class.format_recus([delivre])
      expect(ligne).to eq 'Vaimiti HOA (vaimiti@exemple.pf) — dossier 655888 — déposé le 15/09/2026 — non attendu — ' \
                          'certificat délivré le 07/10/2026'
      expect(described_class.parse_recus(ligne)).to eq [delivre]
    end

    it 'relit une ancienne ligne sans date de délivrance' do
      expect(described_class.parse_recus(texte).map(&:delivre_le)).to eq [nil, nil]
    end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lib/dbs/liste_engagements_spec.rb`
Expected: FAIL (`unknown keywords: delivre_le` ou ligne sans suffixe).

- [ ] **Step 3: Implement** — dans `app/lib/dbs/liste_engagements.rb` :

```ruby
    Engagement = Struct.new(:nom, :email, :numero, :date, :attendu, :delivre_le)

    TIRET = ' — '
    NON_ATTENDU = 'non attendu'
    DELIVRE = 'certificat délivré le'
    LIGNE_RECU = %r{\A(?<nom>.*?) ?\((?<email>[^)]*)\)#{TIRET}dossier (?<numero>\d+)#{TIRET}déposé le (?<date>\d{2}/\d{2}/\d{4})(?<suffixe>#{TIRET}#{NON_ATTENDU})?(?:#{TIRET}#{DELIVRE} (?<delivre>\d{2}/\d{2}/\d{4}))?\z}
```

Dans `parse_recus`, construire avec `delivre_le: m[:delivre] && date_ou_nil(m[:delivre])` :

```ruby
        Engagement.new(nom: m[:nom], email: m[:email].downcase, numero: m[:numero].to_i,
                       date: date, attendu: m[:suffixe].nil?,
                       delivre_le: m[:delivre] && date_ou_nil(m[:delivre]))
```

Dans `format_recus` :

```ruby
      engagements.sort_by(&:numero).map do |e|
        ligne = "#{e.nom} (#{e.email})#{TIRET}dossier #{e.numero}#{TIRET}déposé le #{e.date.strftime('%d/%m/%Y')}"
        ligne += "#{TIRET}#{NON_ATTENDU}" unless e.attendu
        ligne += "#{TIRET}#{DELIVRE} #{e.delivre_le.strftime('%d/%m/%Y')}" if e.delivre_le
        ligne
      end.join("\n")
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/lib/dbs/liste_engagements_spec.rb`
Expected: PASS (tous les exemples, anciens compris).

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/lib/dbs/liste_engagements.rb spec/lib/dbs/liste_engagements_spec.rb
git add app/lib/dbs/liste_engagements.rb spec/lib/dbs/liste_engagements_spec.rb
git commit -m "feat(dbs): lignes d'engagement — mention « certificat délivré le J »"
```

---

### Task 2: `Dbs::EngagementRecu` — poser la date de délivrance

**Files:**
- Modify: `app/lib/dbs/engagement_recu.rb`
- Test: `spec/lib/dbs/engagement_recu_spec.rb`

**Interfaces:**
- Consumes: `Engagement#delivre_le` (Task 1).
- Produces: nouvelle clé optionnelle du sous-bloc `engagement:` : `certificat` (libellé de l'annotation pièce jointe, défaut `nil`). Règle : `delivre_le = date de traitement` **si** l'engagement est `accepte` **et** l'annotation `certificat` contient au moins un fichier ; sinon `nil`. `version` passe à `super + 5` (retraitement des engagements déjà acceptés).

- [ ] **Step 1: Write the failing tests** — dans `spec/lib/dbs/engagement_recu_spec.rb`, ajouter `certificat: "Certificat d'isolement délivré"` au sous-bloc `engagement:` de `let(:task)`, puis :

```ruby
  context 'quand l engagement est accepté' do
    let(:fichiers) { [double('Fichier', filename: 'Certificat 655888.pdf')] }
    let(:engagement) do
      double('Engagement', number: 655_888, state: 'accepte', date_depot: '2026-09-15T22:00:00+00:00',
                           date_traitement: '2026-10-07T09:30:00-10:00',
                           usager: double('Usager', email: 'Vaimiti@exemple.pf'),
                           demandeur: double('PersonneMorale', entreprise: double('Entreprise', raison_sociale: 'EARL HOA')),
                           champs: [lien, champ("Nom et prénom de l'éleveur", 'Vaimiti HOA'), champ('Téléphone', telephone_engagement)],
                           annotations: [champ("Courriel d'attribution", attribution_existante),
                                         double('PJ', label: "Certificat d'isolement délivré", __typename: 'PieceJustificativeChamp',
                                                      files: fichiers, string_value: '')])
    end

    it 'ajoute la date de délivrance du certificat à sa ligne' do
      task.process(demarche, engagement)
      expect(SetAnnotationValue).to have_received(:set_value).with(
        laissez_passer, 'robot', 'Engagements reçus',
        'Vaimiti HOA (vaimiti@exemple.pf) — dossier 655888 — déposé le 15/09/2026 — certificat délivré le 07/10/2026'
      )
    end

    context 'sans certificat (accepté à la main)' do
      let(:fichiers) { [] }

      it 'ne dit pas « certificat délivré »' do
        task.process(demarche, engagement)
        expect(SetAnnotationValue).to have_received(:set_value).with(
          laissez_passer, 'robot', 'Engagements reçus',
          'Vaimiti HOA (vaimiti@exemple.pf) — dossier 655888 — déposé le 15/09/2026'
        )
      end
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lib/dbs/engagement_recu_spec.rb`
Expected: FAIL (`certificat n'existe pas dans engagement` puis ligne sans suffixe).

- [ ] **Step 3: Implement** — dans `app/lib/dbs/engagement_recu.rb` :

```ruby
    ENGAGEMENT_DEFAUTS = { nom: "Nom et prénom de l'éleveur", telephone: 'Téléphone',
                           courriel_attribution: nil, certificat: nil }.freeze
```

`version` : `super + 5`. Dans `engagement_courant` :

```ruby
    def engagement_courant(eleveurs, email)
      ListeEngagements::Engagement.new(nom: nom_eleveur, email:, numero: @dossier.number,
                                       date: date_depot,
                                       attendu: eleveurs.any? { |e| e[:email] == email },
                                       delivre_le: certificat_delivre_le)
    end

    # Date de délivrance du certificat d'isolement : l'engagement est accepté ET son annotation certificat
    # contient un fichier (un engagement accepté à la main, sans certificat, n'en a pas).
    def certificat_delivre_le
      return nil unless @dossier.state == 'accepte' && @engagement[:certificat].present?

      pj = annotation(@engagement[:certificat], warn_if_empty: false)
      return nil if pj.nil? || pj.files.blank?

      Time.zone.parse(@dossier.date_traitement.to_s)&.to_date
    end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/lib/dbs/engagement_recu_spec.rb spec/lib/dbs/liste_engagements_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/lib/dbs/engagement_recu.rb spec/lib/dbs/engagement_recu_spec.rb
git add app/lib/dbs/engagement_recu.rb spec/lib/dbs/engagement_recu_spec.rb
git commit -m "feat(dbs): engagement accepté avec certificat — date de délivrance sur le laissez-passer"
```

---

### Task 3: `Dbs::ReferencesLaissezPasser` — référence 6/ = certificats délivrés

**Files:**
- Modify: `app/lib/dbs/references_laissez_passer.rb` (méthode `certificats_isolement`, `version`)
- Test: `spec/lib/dbs/references_laissez_passer_spec.rb`

**Interfaces:**
- Consumes: `Engagement#delivre_le` (Task 1).
- Produces: `output["Certificats d'isolement"]` ne contient que les engagements dont `delivre_le` est renseigné, `'date'` = date de délivrance ; rangs consécutifs à partir de 6. `version` : `super + 4`.

- [ ] **Step 1: Write the failing tests** — dans le spec, remplacer `let(:engagements_recus)` par des lignes à suffixe et adapter le test des certificats :

```ruby
  let(:engagements_recus) do
    "Jean DUPONT (jean@dupont.pf) — dossier 680145 — déposé le 01/10/2026 — certificat délivré le 03/10/2026\n" \
      "Sébastien MOLLARD (seb@ferme.pf) — dossier 680123 — déposé le 30/09/2026 — certificat délivré le 02/10/2026\n" \
      'Paul ATTENTE (paul@attente.pf) — dossier 680150 — déposé le 02/10/2026'
  end
```

```ruby
    it 'cite les seuls certificats délivrés, datés de leur délivrance, à partir de 6/' do
      expect(subject["Certificats d'isolement"]).to eq [
        { 'rang' => 6, 'numero' => 680_123, 'date' => '02/10/2026', 'site' => 'TAMARU FARM', 'fin' => ' ;' },
        { 'rang' => 7, 'numero' => 680_145, 'date' => '03/10/2026', 'site' => 'Ferme Dupont', 'fin' => '' }
      ]
    end

    context 'sans aucun certificat délivré' do
      let(:engagements_recus) { 'Paul ATTENTE (paul@attente.pf) — dossier 680150 — déposé le 02/10/2026' }

      it 'rend une liste vide' do
        expect(subject["Certificats d'isolement"]).to eq []
      end
    end
```

Adapter aussi le contexte « engagement non attendu » : sa ligne devient
`'Paul INCONNU (paul@x.pf) — dossier 680200 — déposé le 01/10/2026 — non attendu — certificat délivré le 02/10/2026'`.

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lib/dbs/references_laissez_passer_spec.rb`
Expected: FAIL (680150 présent, dates de dépôt au lieu de délivrance).

- [ ] **Step 3: Implement**

```ruby
    def certificats_isolement(dossier, eleveurs)
      delivres = ListeEngagements.parse_recus(texte_annotation(dossier, @cfg[:engagements_recus]))
                                 .select(&:delivre_le).sort_by(&:numero)
      delivres.each_with_index.map do |e, i|
        { 'rang' => PREMIER_RANG + i, 'numero' => e.numero, 'date' => e.delivre_le.strftime('%d/%m/%Y'),
          'site' => site(e, eleveurs, dossier), 'fin' => i < delivres.size - 1 ? ' ;' : '' }
      end
    end
```

`version` : `super + 4`. Mettre à jour le commentaire d'en-tête de la classe (« une référence numérotée par certificat d'isolement **délivré** »).

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/lib/dbs/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/lib/dbs/references_laissez_passer.rb spec/lib/dbs/references_laissez_passer_spec.rb
git add app/lib/dbs/references_laissez_passer.rb spec/lib/dbs/references_laissez_passer_spec.rb
git commit -m "feat(dbs): laissez-passer — la référence 6 ne cite que les certificats délivrés"
```

---

### Task 4: calcul générique `calculs/te_fenua`

**Files:**
- Create: `app/lib/calculs/te_fenua.rb`
- Test: `spec/lib/calculs/te_fenua_spec.rb`

**Interfaces:**
- Produces: tâche `calculs/te_fenua` (paramètre requis `champ` : libellé du champ carte). `process_row(dossier, output)` écrit, pour le **premier marqueur** : `"<champ>.commune"`, `"<champ>.ile"`, `"<champ>.parcelle"` (« AB 5 »), `"<champ>.lieu"` (« PAPEETE (Tahiti), parcelle AB 5 » ; sans parcelle : « PAPEETE (Tahiti) »). Champ absent, vide, sans marqueur ou JSON invalide → les quatre clés valent `''`. Dans un gabarit : `adresse_du_lieu_d_isolement_lieu`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Calculs::TeFenua do
  let(:calcul) { described_class.new({ 'champ' => "Adresse du lieu d'isolement" }) }
  let(:geo) do
    { markers: { type: 'FeatureCollection',
                 features: [{ type: 'Feature', geometry: { type: 'Point', coordinates: [-149.578, -17.544] },
                              properties: { commune: 'PAPEETE', ile: 'Tahiti', section: 'AB', numero: '5' } }] } }.to_json
  end
  let(:valeur) { geo }
  let(:dossier) do
    double('Dossier', champs: [double('Carte', label: "Adresse du lieu d'isolement", __typename: 'TeFenuaChamp',
                                                string_value: valeur)], annotations: [])
  end

  subject { {}.tap { |output| calcul.process_row(dossier, output) } }

  it 'décrit le lieu par commune, île et parcelle' do
    expect(subject["Adresse du lieu d'isolement.lieu"]).to eq 'PAPEETE (Tahiti), parcelle AB 5'
    expect(subject["Adresse du lieu d'isolement.commune"]).to eq 'PAPEETE'
    expect(subject["Adresse du lieu d'isolement.parcelle"]).to eq 'AB 5'
  end

  context 'sans parcelle' do
    let(:valeur) { geo.sub('"section":"AB","numero":"5"', '"section":null,"numero":null') }

    it 'garde commune et île' do
      expect(subject["Adresse du lieu d'isolement.lieu"]).to eq 'PAPEETE (Tahiti)'
    end
  end

  [nil, '', '{"markers":{"features":[]}}', 'pas du json'].each do |vide|
    context "avec la valeur #{vide.inspect}" do
      let(:valeur) { vide }

      it 'rend des chaînes vides sans lever' do
        expect(subject["Adresse du lieu d'isolement.lieu"]).to eq ''
      end
    end
  end

  it 'exige le paramètre champ' do
    expect(described_class.new({}).errors.join).to include('champ')
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lib/calculs/te_fenua_spec.rb`
Expected: FAIL (`uninitialized constant Calculs::TeFenua`).

- [ ] **Step 3: Implement** — `app/lib/calculs/te_fenua.rb` :

```ruby
# frozen_string_literal: true

module Calculs
  # Lit un champ carte Te Fenua : sa valeur est un GeoJSON dont chaque marqueur porte la commune, l'île et la
  # parcelle cadastrale (section, numéro). Le robot ne sait pas l'afficher autrement que « TeFenuaChamp » : ce
  # calcul en tire un texte imprimable. Seul le premier marqueur compte.
  class TeFenua < FieldChecker
    CLES = %w[commune ile parcelle lieu].freeze

    def version
      super + 1
    end

    def required_fields
      super + %i[champ]
    end

    def process_row(dossier, output)
      libelle = @params[:champ]
      proprietes = premier_marqueur(dossier, libelle)
      valeurs = decrire(proprietes)
      CLES.each { |cle| output["#{libelle}.#{cle}"] = valeurs[cle] }
    end

    private

    def premier_marqueur(dossier, libelle)
      champ = object_field_values(dossier, libelle, log_empty: false).first
      texte = champ&.string_value.to_s
      return {} if texte.blank?

      JSON.parse(texte).dig('markers', 'features', 0, 'properties') || {}
    rescue JSON::ParserError
      {}
    end

    def decrire(proprietes)
      commune = proprietes['commune'].to_s
      ile = proprietes['ile'].to_s
      parcelle = [proprietes['section'], proprietes['numero']].compact.join(' ').strip
      lieu = [commune, ile.present? && "(#{ile})"].select(&:present?).join(' ')
      lieu = [lieu, parcelle.present? && "parcelle #{parcelle}"].select(&:present?).join(', ') if lieu.present?
      { 'commune' => commune, 'ile' => ile, 'parcelle' => parcelle, 'lieu' => lieu.to_s }
    end
  end
end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/lib/calculs/te_fenua_spec.rb`
Expected: PASS (7 exemples).

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/lib/calculs/te_fenua.rb spec/lib/calculs/te_fenua_spec.rb
git add app/lib/calculs/te_fenua.rb spec/lib/calculs/te_fenua_spec.rb
git commit -m "feat(calculs): te_fenua — commune, île et parcelle d'un champ carte"
```

---

### Task 5: démarches 4038 et 3899 — annotations (MCP)

**Files:** aucun fichier du dépôt ; modifications des révisions brouillon par le MCP `mes-demarches`.

**Interfaces:**
- Produces (libellés exacts utilisés par Tasks 6-7) : 4038 « Visa de l'agent habilité » (visa), « Certificat d'isolement délivré » (pièce jointe) ; 3899 « Pays d'origine » et « Demande déposée le » (formules d'annotation).

- [ ] **Step 1: 4038 — ajouts.** Avec `mcp__mes-demarches__ajouter_champ` (démarche 4038, `prive: true`) :
  - `visa`, libellé « Visa de l'agent habilité », après « Carnet de notes » (197036), description : « Le visa valide l'engagement : le robot génère le certificat d'isolement, le range ci-dessous et accepte le dossier ; le mail d'acceptation envoie le certificat à l'éleveur. », options `{"accredited_users": ["clautier@idt.pf", "timeri.galenon@administration.gov.pf", "severine.sampietro@administration.gov.pf"]}` ;
  - `piece_justificative`, libellé « Certificat d'isolement délivré », après « Courriel d'attribution » (197081), description : « Généré par le robot au visa de l'engagement. »

- [ ] **Step 2: 4038 — suppressions.** `mcp__mes-demarches__supprimer_champ` sur 197028 (« Laissez-passer visé le ») et 197030 (« Certificat d'isolement établi le »). Vérifier d'abord qu'aucun YAML ne les cite : `grep -rn "visé le\|établi le" storage/configurations/` → aucun résultat.

- [ ] **Step 3: 3899 — formules d'annotation.** `mcp__mes-demarches__ajouter_champ` (démarche 3899, `prive: true`, `typeChamp: formule`), après « Expéditeur sur le laissez-passer » (197872) :
  - « Pays d'origine » : `SI({Provenance} == "Autre pays", {Pays de provenance}, {Provenance})`, description « Calculé : imprimé sur le certificat d'isolement. » ;
  - « Demande déposée le » : `CONCATENER(SI(JOUR({Date de dépôt}) < 10, "0", ""), ENTIER(JOUR({Date de dépôt})), "/", SI(MOIS({Date de dépôt}) < 10, "0", ""), ENTIER(MOIS({Date de dépôt})), "/", ENTIER(ANNEE({Date de dépôt})))`, description « Calculé : date de dépôt (jour seul), imprimée sur le certificat d'isolement. »

- [ ] **Step 4: Vérifier** par lecture de la révision brouillon :

```bash
bin/rails runner '
%w[4038 3899].each do |n|
  r = MesDemarches.query(MesDemarches::Queries::DemarcheRevision, variables: { demarche: n.to_i })
  puts "== #{n}"; r.data.demarche.draft_revision.annotation_descriptors.each { |d| puts "  #{d.label} [#{d.__typename}]" }
end'
```

Expected : 4038 contient « Visa de l'agent habilité » et « Certificat d'isolement délivré », plus « Laissez-passer visé le » ni « Certificat d'isolement établi le » ; 3899 contient « Pays d'origine » et « Demande déposée le ».

- [ ] **Step 5: Consigner** les stable_id créés dans la spec (§3) et commiter la spec.

---

### Task 6: gabarit `Certificat d'isolement.docx`

**Files:**
- Create: `storage/models/dbs/poussins/Certificat d'isolement.docx` (non versionné)
- Script de construction (scratchpad, non versionné) : `gabarit_certificat.py`

**Interfaces:**
- Consumes : clés de publipostage de Task 7 — colonnes `dossier`, `depot_engagement`, `importateur`, `date_arrivee`, `vol`, `effectif`, `eleveur`, `etablissement`, `adresse_importateur`, `permis`, `lot_total`, `expediteur`, `pays_origine`, `demande`, `demande_date` ; clés calculées `aujourd_hui`, `dernier_instructeur_prenom`, `dernier_instructeur_nom`, `visa_de_l_agent_habilite_prenom`, `visa_de_l_agent_habilite_nom`, `visa_de_l_agent_habilite_fonction`, `adresse_du_lieu_d_isolement_lieu`.

- [ ] **Step 1: Construire** à partir de la première partie de `docs/dbs/import_volaille/Certificat d'isolement poussin d'un jour et suite administrative  doc vierge .docx` (paragraphes jusqu'à « Détenteur » inclus ; tout ce qui suit « SUITE ADMINISTRATIVE » est supprimé). Même technique que le gabarit du laissez-passer : réécrire les paragraphes en `w:fldSimple MERGEFIELD` (style du run d'origine, surlignage retiré, `<w:br/>` conservés), purger `DocRef`, `Prop_Pays`, `AnimalNumID`. Correspondances :

| Texte du modèle | Remplacé par |
|---|---|
| `N° --- / MPR / DBS / ZOO` | `N° «=dossier» / MPR / DBS / ZOO` |
| `Faa'A, le ------` | `Faa'a, le «=aujourd_hui»` |
| `Dossier suivi par : ----` | `«=dernier_instructeur_prenom» «=dernier_instructeur_nom»` |
| `Je soussigné(e), Séverine SAMPIETRO vétérinaire officielle …, originaires de Nouvelle-Zélande, …` | `Je soussigné(e), «=visa_de_l_agent_habilite_prenom» «=visa_de_l_agent_habilite_nom», «=visa_de_l_agent_habilite_fonction» de la cellule zoosanitaire …, originaires de «=pays_origine», …` |
| Date de l'arrivée | `«=date_arrivee»` |
| Moyen de transport | `Vol «=vol»` |
| Nom de l'importateur | `«=importateur»` |
| Adresse de l'importateur (ligne BP/tél) | `«=adresse_importateur»` |
| Permis d'importation | `«=permis»` |
| Lot total importé | `«=lot_total» poussins d'un jour` |
| Nom de l'expéditeur | `«=expediteur»` |
| Date / Numéro du certificat sanitaire (2 lignes) | **supprimées** ; à la place : `Demande de laissez-passer : n° «=demande» du «=demande_date»` |
| Nombre de poussins mis à l'isolement | `«=effectif»` |
| Pour l'établissement … Appartenant à … | `«=etablissement»` … `«=eleveur»` |
| Adresse du lieu d'isolement | `«=adresse_du_lieu_d_isolement_lieu»` |
| `Signature et cachet` / `Vétérinaire officielle` | `Cachet` / `«=visa_de_l_agent_habilite_fonction»` |
| `Signature précédée de la mention « lu et approuvé »` / `Détenteur` | `Engagements souscrits par le détenteur sur Mes-Démarches le «=depot_engagement» (dossier n° «=dossier»)` |

- [ ] **Step 2: Tampon** — copier l'image du tampon depuis `storage/models/dbs/poussins/Laissez-passer poussins.docx` : le run `<w:drawing>` du paragraphe de signature, le fichier `word/media/…` qu'il référence, et sa relation dans `word/_rels/document.xml.rels` (nouvel identifiant `rId` libre) ; l'insérer dans le paragraphe « Cachet ».

- [ ] **Step 3: Contrôler** : `unzip -p … word/document.xml | grep -o 'MERGEFIELD [^ ]*' | sort -u` liste exactement les 22 clés distinctes de l'interface (24 champs : `dossier` et `visa_de_l_agent_habilite_fonction` apparaissent deux fois) ; aucun `DocRef`/`Prop_Pays`/`AnimalNumID`.

- [ ] **Step 4: Faire relire** le gabarit par l'utilisateur dans Word (retouches esthétiques) ; **sa version retouchée devient la référence** — ne plus la régénérer par script.

---

### Task 7: chaîne YAML côté engagement, contrôle de bout en bout, déploiement

**Files:**
- Modify: `storage/configurations/dbs_poussins.yml` (bloc `dbs_poussins_engagement`, nouvelles ancres)

**Interfaces:**
- Consumes : Tasks 1-6.

- [ ] **Step 1: Ancre de publipostage du certificat** (après `dbs_poussins_publipostage_lp`) :

```yaml
dbs_poussins_publipostage_certificat: &dbs_poussins_publipostage_certificat
  etat_du_dossier: [ en_construction, en_instruction ]
  modele: "dbs/poussins/Certificat d'isolement.docx"
  type_de_document: pdf
  nom_fichier: Certificat d'isolement {number}
  message: Certificat d'isolement du dossier {number}   # requis ; non envoyé (champ_cible), l'éleveur reçoit le mail d'acceptation
  champ_cible: Certificat d'isolement délivré
  calculs:
    - calculs/email_to_names:
        fonction_par_défaut: Contrôleur biosécurité
        mails: *dbs_poussins_agents
    - calculs/te_fenua:
        champ: Adresse du lieu d'isolement
  # Valeurs calculées lues sous leur nom normalisé : dernier_instructeur_*, visa_de_l_agent_habilite_*,
  # adresse_du_lieu_d_isolement_lieu ; date du document = aujourd_hui. Données du lot : demande liée (chemins pointés).
  champs:
    - { colonne: dossier, champ: number }
    - { colonne: depot_engagement, champ: date_depot }
    - { colonne: importateur, champ: Importateur du lot }
    - { colonne: date_arrivee, champ: Date d'arrivée prévue du lot }
    - { colonne: vol, champ: Numéro du vol d'arrivée }
    - { colonne: effectif, champ: Effectif attribué à votre élevage }
    - { colonne: eleveur, champ: Nom et prénom de l'éleveur }
    - { colonne: etablissement, champ: demandeur.entreprise.raison_sociale }
    - { colonne: demande, champ: Numéro du dossier de laissez-passer.number }
    - { colonne: demande_date, champ: Numéro du dossier de laissez-passer.Demande déposée le }
    - { colonne: adresse_importateur, champ: Numéro du dossier de laissez-passer.demandeur.adresse }
    - { colonne: permis, champ: Numéro du dossier de laissez-passer.Numéro de permis d'importation préalable }
    - { colonne: lot_total, champ: Numéro du dossier de laissez-passer.Quantité totale }
    - { colonne: expediteur, champ: Numéro du dossier de laissez-passer.Expéditeur sur le laissez-passer }
    - { colonne: pays_origine, champ: Numéro du dossier de laissez-passer.Pays d'origine }
```

- [ ] **Step 2: Chaîne dans `dbs_poussins_engagement`** — `when_ok` : ajouter `certificat: Certificat d'isolement délivré` au sous-bloc `engagement:` de `dbs/engagement_recu`, puis, **après** cette tâche :

```yaml
    # Visa de l'engagement → certificat → acceptation, en un seul passage (conditional_field relit le dossier
    # après une tâche qui l'a modifié et n'intercepte pas les erreurs). L'acceptation modifie l'engagement :
    # au passage suivant, dbs/engagement_recu note « certificat délivré le J » sur le laissez-passer.
    - conditional_field:
        etat_du_dossier: [ en_construction, en_instruction ]
        champ: Visa de l'agent habilité
        valeurs:
          "":
          par défaut:
            - publipostage_v3: *dbs_poussins_publipostage_certificat
            - conditional_field:
                champ: Certificat d'isolement délivré
                valeurs:
                  "":
                  par défaut:
                    - dossier_accepter:
```

- [ ] **Step 3: Instancier toutes les tâches** (y compris imbriquées) — aucune erreur :

```bash
bin/rails runner '
y = YAML.load_file("storage/configurations/dbs_poussins.yml", aliases: true)
wo = y["dbs_poussins_engagement"]["when_ok"]
InspectorTask.create_tasks(wo).each { |t| puts "#{t.class} #{t.errors.inspect}" }
subs = wo.last["conditional_field"]["valeurs"]["par défaut"]
InspectorTask.create_tasks(subs).each { |t| puts "  #{t.class} #{t.errors.inspect}" }
PublipostageV3.new(y["dbs_poussins_publipostage_certificat"]).instance_variable_get(:@calculs).each { |c| puts "  #{c.class} #{c.errors.inspect}" }'
```

Expected : toutes les listes d'erreurs vides.

- [ ] **Step 4: Rendu de bout en bout sur l'engagement 683297** (sans rien envoyer) : rejouer `get_fields` + `compute_dynamic_fields` + `add_volatile_fields` + `normalize_context` + `Sablon.template(...).render_to_file` (même script que pour le laissez-passer, avec `dbs_poussins_publipostage_certificat`), convertir en PDF avec `soffice --headless --convert-to pdf`, puis :

Run: `pdftotext -layout cert_683297.pdf - | grep '«' | grep -vc Télérecours`
Expected: `0` ; relire le PDF (lot, élevage, lieu « … (Tahiti), parcelle … », signataire, mention du détenteur, tampon).

- [ ] **Step 5: Livrer** : specs `spec/lib/dbs spec/lib/calculs` vertes et `bundle exec rubocop --parallel` sans offense ; fusionner `dbs-poussins-cascade` dans `dev` (worktree sur `origin/dev`, `.env` lié, `git merge --no-ff`, specs `spec/lib spec/jobs` vertes) puis `git push origin <branche-worktree>:dev`. Publier le gabarit (`mc cp` depuis `storage/models/…`) et le YAML (`mc cp` depuis `storage/configurations/…`) vers `rmds/robot-mes-demarches-staging/…`, avec copies dans `deployment/robot-mes-demarches-staging/` ; vérifier tailles (`mc ls`) et etag du YAML. Mettre à jour la spec (§3 stable_id, statut) et la mémoire projet.
