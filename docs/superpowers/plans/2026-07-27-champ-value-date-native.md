# Dates natives dans `champ_value` (DateValue / DatetimeValue) — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `champ_value` doit rendre les dates sous forme d'objet date exploitable par les plugins (comparaisons, arithmétique) sans changer une seule ligne de sortie des documents, messages et mutations existants.

**Architecture:** On n'ajoute pas de méthode d'accès parallèle et on ne déplace pas le formatage chez les appelants : on introduit `DateValue < Date` et `DatetimeValue < DateTime` dont le seul comportement redéfini est `to_s`, qui rend le format français. Toute la couche d'affichage existante (`join`, `humanize`, Sablon, `value&.to_s` de `ConditionalField`) continue donc à produire exactement les mêmes chaînes, tandis que les plugins reçoivent un vrai `Date`. C'est la transposition du pattern `BooleanValue` (`app/lib/boolean_value.rb`) déjà introduit par PublipostageV3 pour les cases à cocher.

**Tech Stack:** Ruby 3.x / Rails, RSpec, RubyXL (export Excel), Sablon (publipostage), graphql-client.

## Contexte : pourquoi ce plan existe

`graphql_champ_value` (`app/lib/field_checker.rb:158`) renvoie aujourd'hui `'27/07/2026'` pour un `DateChamp`. Un plugin qui a besoin de la date doit donc la reparser, et `Date.parse` sur une chaîne française est ambigu. C'est ce qui a produit l'incident daeth du 27/07/2026 (corrigé par 2664e06, qui contourne le problème avec `raw_date_value` en local).

Le réflexe « faire renvoyer un `Date` nu et corriger les appelants » ne marche pas : `champ_value` n'est presque jamais appelé *pour une date*, il est appelé **génériquement sur tous les champs** par `champs_to_values` (`app/lib/field_checker.rb:145`), qui alimente `instanciate_once` (messages, sujets de mail, conditions) et `Publipostage#get_fields` (champs de fusion .docx). Un `Date` nu ferait passer *toutes* les dates de *tous* les templates de `27/07/2026` à `2026-07-27` (`Date#to_s` est ISO), sans aucun appelant identifiable à corriger.

### Hypothèses techniques déjà validées

Un prototype a été exécuté avant rédaction (`DateValue < Date` avec `to_s` redéfini) ; résultats :

| Point de passage | Résultat |
|---|---|
| `DateValue.iso8601('2026-07-27').class` | `DateValue` (les constructeurs de classe de `Date` respectent la sous-classe) |
| `to_s` / `[x].join(', ')` | `27/07/2026` — identique à aujourd'hui |
| `as_json` / `to_json` | `"2026-07-27"` — **ISO préservé** (ActiveSupport utilise `strftime`, pas `to_s`) donc les mutations GraphQL restent correctes |
| `[*value]` (utilisé par `Publipostage#generate_docx`) | 1 élément — pas d'explosion en tableau |
| `case value when Date` | matche → `SetAnnotationValue.typed_query` choisit `SetDate` |
| `d == Date.new(...)`, `d + 1`, `[a, d].max` | fonctionnent, `d + 1` reste un `DateValue` |
| `YAML.dump` | scalaire date `2026-07-27` (pas de tag `!ruby/object:`) |

**Piège identifié :** `DatetimeValue` doit hériter de `DateTime`, **pas** de `Time`. `Time#to_a` existe, donc `[*time]` exploserait en 10 éléments dans `generate_docx`. `DateTime` (sous-classe de `Date`) n'a pas de `to_a`.

## Global Constraints

- Avant chaque commit : `bundle exec rubocop -A <fichiers touchés>` puis `bundle exec rake lint` (règle CLAUDE.md, non négociable).
- Aucun bump de `version` de plugin dans ce chantier : le formatage de sortie est inchangé, il n'y a rien à retraiter. Si une tâche change une sortie visible (Task 5), le signaler et demander avant de bumper.
- Référence de non-régression : `bundle exec rspec` doit finir avec **exactement 3 échecs pré-existants**, tous dans `spec/requests/admin/schema_builder_spec.rb` (chantier schema_builder en cours, sans rapport). Tout 4ᵉ échec est une régression introduite par ce plan.
- Format d'affichage à préserver au caractère près pour les `DateChamp` : `%d/%m/%Y` — c'est ce que `champ_value` produit déjà.
- **Une seule sortie change dans ce chantier, et c'est un choix explicite** (arbitré le 27/07/2026, voir ci-dessous) : les `DatetimeChamp`. Tout le reste doit sortir au caractère près comme avant.

## Décision : les champs date-heure gagnent l'heure

Constat fait en cours d'exécution : aujourd'hui `graphql_champ_value` traite `DatetimeChamp` et `DateChamp` dans **la même branche** avec le format `%d/%m/%Y` (`app/lib/field_checker.rb:174-175`), donc **l'heure d'un champ date-heure est perdue à l'affichage**, alors que les deux autres chemins de formatage du framework l'affichent (`champ_value` sur objet Ruby, `app/lib/field_checker.rb:150`, et `humanize`, `:393`). C'est un oubli, pas une intention.

Décision retenue : `DatetimeChamp` rend un `DatetimeValue`, qui s'affiche `27/07/2026 à 09h30`. C'est un changement de sortie visible sur les templates et messages qui affichent un champ date-heure, assumé comme une correction. En contrepartie, `DatetimeValue` expose une méthode `date` qui rend la date seule, utilisable directement dans un template Sablon de PublipostageV3 : `«=mon_champ.date»` → `27/07/2026`. Vérifié dans la gem : `Sablon::Operations::LookupOrMethodCall#evaluate` (sablon-0.4.3, `lib/sablon/operations.rb:167-179`) fait `local.public_send(m) if local.respond_to?(m)`, donc un appel de méthode sur la valeur du contexte fonctionne — c'est déjà le mécanisme qui sert pour `PieceJustificativeFile` en V3.
- Commits en français, style du dépôt (`fix(scope):` / `feat(scope):`), avec `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.

## Structure des fichiers

| Fichier | Responsabilité |
|---|---|
| `app/lib/date_value.rb` (créer) | `DateValue < Date` : un `Date` qui s'affiche en français. Aucune autre logique. |
| `app/lib/datetime_value.rb` (créer) | `DatetimeValue < DateTime` : idem pour les date-heures. |
| `spec/lib/date_value_spec.rb` (créer) | Contrat des deux classes, y compris les points de passage load-bearing (`as_json`, splat, `case/when`). |
| `app/lib/field_checker.rb` (modifier) | Bascule de `graphql_champ_value` : `DateChamp`/`DatetimeChamp` → objet typé au lieu d'une chaîne. |
| `spec/lib/field_checker_date_spec.rb` (créer) | Tests de caractérisation des chemins de sortie : ce qui sort de `champ_value`, `champs_to_values`, `instanciate`. Écrits **avant** la bascule, doivent rester verts après. |
| `app/lib/excel/from_repetitions.rb` (modifier) | Seul appelant de `graphql_champ_value` hors `field_checker` : écrit dans une cellule RubyXL et dans un YAML d'empreinte → doit recevoir une chaîne, pas un objet date. |
| `spec/lib/excel/from_repetitions_spec.rb` (créer) | Garde sur la valeur de cellule. |
| `app/lib/travail/daeth.rb` + `spec/lib/travail/daeth_spec.rb` (modifier, Task 5) | Nettoyage du contournement local devenu redondant. |

---

### Task 1 : Les deux classes de valeur

**Files:**
- Create: `app/lib/date_value.rb`
- Create: `app/lib/datetime_value.rb`
- Test: `spec/lib/date_value_spec.rb`

**Interfaces:**
- Consomme : rien.
- Produit : `DateValue.iso8601(String) -> DateValue`, `DatetimeValue.iso8601(String) -> DatetimeValue`, tous deux `is_a?(Date)`, `to_s` en format français. Utilisés par la Task 4.

- [ ] **Step 1 : Écrire le test qui échoue**

Créer `spec/lib/date_value_spec.rb` :

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DateValue do
  subject(:date) { described_class.iso8601('2026-07-27') }

  it 'reste construite dans sa propre classe' do
    expect(date).to be_a(described_class)
    expect(date).to be_a(Date)
  end

  it "s'affiche au format français" do
    expect(date.to_s).to eq('27/07/2026')
    expect("le #{date}").to eq('le 27/07/2026')
    expect([date].join(', ')).to eq('27/07/2026')
  end

  # Load-bearing : les mutations GraphQL sérialisent la valeur en JSON
  # (SetAnnotationValue.raw_set_value passe `value:` tel quel au client).
  # Un ISO8601Date est attendu côté serveur.
  it 'se sérialise en ISO en JSON' do
    expect(date.as_json).to eq('2026-07-27')
    expect({ value: date }.to_json).to eq('{"value":"2026-07-27"}')
  end

  # Load-bearing : Publipostage#generate_docx fait `[*v].join(', ')`.
  it 'ne se disperse pas au splat' do
    expect([*date].size).to eq(1)
  end

  # Load-bearing : SetAnnotationValue.typed_query dispatche sur la classe.
  it 'matche `when Date` dans un case' do
    branch = case date
             when String then 'String'
             when Date then 'Date'
             end
    expect(branch).to eq('Date')
  end

  it 'garde le comportement arithmétique et comparatif de Date' do
    expect(date).to eq(Date.new(2026, 7, 27))
    expect(date + 1).to eq(Date.new(2026, 7, 28))
    expect([Date.new(2026, 1, 1), date].max).to eq(date)
    expect(date).to be_present
  end
end

RSpec.describe DatetimeValue do
  subject(:datetime) { described_class.iso8601('2026-07-27T09:30:00+10:00') }

  it "s'affiche au format français avec l'heure" do
    expect(datetime.to_s).to eq('27/07/2026 à 09h30')
  end

  # Contre-exemple volontaire : hériter de Time donnerait `[*value].size == 10`
  # (Time#to_a) et casserait Publipostage#generate_docx.
  it 'hérite de DateTime et non de Time' do
    expect(datetime).to be_a(DateTime)
    expect([*datetime].size).to eq(1)
  end

  it 'se sérialise en ISO en JSON' do
    expect(datetime.as_json).to start_with('2026-07-27T09:30:00')
  end
end
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `bundle exec rspec spec/lib/date_value_spec.rb`
Expected: FAIL — `uninitialized constant DateValue`

- [ ] **Step 3 : Écrire l'implémentation minimale**

Créer `app/lib/date_value.rb` :

```ruby
# frozen_string_literal: true

# Date d'un champ Mes-Démarches : un vrai `Date`, manipulable par les plugins
# (comparaisons, arithmétique, `Date` dans un `case`), mais qui s'affiche au
# format français dès qu'il est interpolé dans un message, un champ de fusion
# .docx ou un `join`.
#
# C'est la transposition aux dates du pattern `BooleanValue` : le type reste
# natif, seul l'affichage est francisé. La sérialisation JSON reste ISO8601
# (ActiveSupport passe par `strftime`, pas par `to_s`), ce qui garantit que les
# mutations GraphQL `ISO8601Date` continuent de partir correctement.
class DateValue < Date
  def to_s
    strftime('%d/%m/%Y')
  end
end
```

Créer `app/lib/datetime_value.rb` :

```ruby
# frozen_string_literal: true

# Pendant de `DateValue` pour les champs date-heure.
#
# Hérite de `DateTime` et **pas** de `Time` : `Time#to_a` existe, donc un splat
# (`[*value]`, utilisé par `Publipostage#generate_docx`) exploserait la valeur en
# dix éléments. `DateTime` est une sous-classe de `Date` et n'a pas de `to_a`.
class DatetimeValue < DateTime
  def to_s
    strftime('%d/%m/%Y à %Hh%M')
  end
end
```

- [ ] **Step 4 : Lancer le test pour vérifier qu'il passe**

Run: `bundle exec rspec spec/lib/date_value_spec.rb`
Expected: PASS (11 exemples)

- [ ] **Step 5 : Lint puis commit**

```bash
bundle exec rubocop -A app/lib/date_value.rb app/lib/datetime_value.rb spec/lib/date_value_spec.rb
bundle exec rake lint
git add app/lib/date_value.rb app/lib/datetime_value.rb spec/lib/date_value_spec.rb
git commit -m "feat(champs): DateValue et DatetimeValue, des dates natives qui s'affichent en français"
```

---

### Task 2 : Tests de caractérisation des chemins de sortie

Ces tests décrivent ce que le framework produit **aujourd'hui** pour un champ date. Ils doivent passer avant la bascule (Task 4) et rester identiques après : c'est le filet qui prouve qu'aucun document ni message ne change.

**Files:**
- Test: `spec/lib/field_checker_date_spec.rb` (créer)

**Interfaces:**
- Consomme : `FieldChecker#champ_value`, `#champs_to_values`, `#instanciate` (tous publics, cf. `app/lib/field_checker.rb:148`, `:144`, `:292`).
- Produit : rien (tests seulement).

- [ ] **Step 1 : Écrire les tests de caractérisation**

Créer `spec/lib/field_checker_date_spec.rb` :

```ruby
# frozen_string_literal: true

require 'rails_helper'

# Caractérisation des sorties produites pour un champ date. Ces attentes portent
# sur des chaînes visibles par les usagers (messages, champs de fusion .docx) :
# elles doivent rester vraies quelle que soit la représentation interne choisie.
RSpec.describe FieldChecker do
  let(:checker) { FieldChecker.new({}) }

  # Un DateChamp réel ne répond pas à `value` : le fragment ChampInfo l'aliase en
  # `dateValue` (commit 0ad4ea8).
  def date_champ(label, iso)
    double(label, label:, __typename: 'DateChamp', date_value: iso)
  end

  let(:champ) { date_champ('Date du jugement', '2026-07-27') }
  let(:dossier) { double('Dossier', number: 123, champs: [champ]) }

  before { checker.instance_variable_set(:@dossier, dossier) }

  it 'interpole la date au format français dans un message' do
    expect(checker.instanciate('Jugement du {Date du jugement}.'))
      .to eq('Jugement du 27/07/2026.')
  end

  it 'produit une valeur affichable au format français' do
    expect(checker.champ_value(champ).to_s).to eq('27/07/2026')
    expect(checker.champs_to_values([champ]).join(', ')).to eq('27/07/2026')
  end

  # Publipostage#generate_docx : `[*v].join(', ')` sur chaque valeur du contexte.
  it 'reste un scalaire une fois splatté comme dans generate_docx' do
    value = checker.champ_value(champ)
    expect([*value].join(', ')).to eq('27/07/2026')
  end

  # ConditionalField#process_condition normalise avec `value&.to_s` avant de
  # chercher la clé dans `valeurs:`.
  it 'se normalise en clé de condition identique' do
    expect(checker.champs_to_values([champ]).first.to_s).to eq('27/07/2026')
  end

  it 'rend une chaîne vide pour un champ date non renseigné' do
    expect(checker.champ_value(date_champ('Date du jugement', nil))).to eq('')
  end

  it 'ne retient pas un champ date vide dans les valeurs' do
    expect(checker.champs_to_values([date_champ('Date du jugement', nil)])).to eq([])
  end
end
```

- [ ] **Step 2 : Lancer les tests — ils doivent déjà passer**

Run: `bundle exec rspec spec/lib/field_checker_date_spec.rb`
Expected: PASS (7 exemples). Un échec ici signifie que la caractérisation est fausse : corriger l'attente pour refléter le comportement réel **avant** de continuer, ne jamais adapter le code de production à cette étape.

- [ ] **Step 3 : Lint puis commit**

```bash
bundle exec rubocop -A spec/lib/field_checker_date_spec.rb
bundle exec rake lint
git add spec/lib/field_checker_date_spec.rb
git commit -m "test(champs): caractériser les sorties produites pour un champ date"
```

---

### Task 3 : Garde sur l'export Excel

`app/lib/excel/from_repetitions.rb` est le seul appelant de `graphql_champ_value` hors de `FieldChecker` (deux sites : `:47` écrit dans une cellule RubyXL, `:87` alimente un `YAML.dump` servant d'empreinte anti-doublon). RubyXL attend une chaîne ou un nombre, et l'empreinte YAML ne doit pas changer de forme. On force donc la conversion en chaîne pour les dates, avant la bascule — ainsi il n'existe aucun état intermédiaire cassé dans l'historique.

**Files:**
- Modify: `app/lib/excel/from_repetitions.rb:41-49` et `:82-90`
- Test: `spec/lib/excel/from_repetitions_spec.rb` (créer)

**Interfaces:**
- Consomme : `FieldChecker#graphql_champ_value`.
- Produit : `Excel::FromRepetitions#champ_cell_value(champ) -> String | Numeric | Array` — jamais un objet date.

- [ ] **Step 1 : Écrire le test qui échoue**

Créer `spec/lib/excel/from_repetitions_spec.rb` :

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Excel::FromRepetitions do
  # `initialize` vérifie l'existence du modèle .xlsx sur le disque.
  let(:controle) { described_class.new(champ_cible: 'Export', modele: 'modele.xlsx') }

  before { allow(File).to receive(:exist?).with('modele.xlsx').and_return(true) }

  # RubyXL#add_cell et le YAML d'empreinte veulent une chaîne : un objet date
  # produirait une cellule typée et une empreinte de forme différente.
  it 'écrit une date de cellule sous forme de chaîne française' do
    champ = double('DateChamp', label: 'Date de début', __typename: 'DateChamp', date_value: '2026-07-27')
    expect(controle.send(:champ_cell_value, champ)).to eq('27/07/2026')
  end

  it 'laisse les autres types inchangés' do
    champ = double('TextChamp', label: 'Nom', __typename: 'TextChamp', value: 'Tavita')
    expect(controle.send(:champ_cell_value, champ)).to eq('Tavita')
  end
end
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `bundle exec rspec spec/lib/excel/from_repetitions_spec.rb`
Expected: FAIL — `champ_cell_value` n'existe pas.

- [ ] **Step 3 : Écrire l'implémentation minimale**

Dans `app/lib/excel/from_repetitions.rb`, remplacer les deux appels à `graphql_champ_value(sous_champ)` (lignes ~47 et ~87) par `champ_cell_value(sous_champ)`, et ajouter la méthode dans la section privée :

```ruby
    # Une cellule Excel et l'empreinte YAML veulent une chaîne : on aplatit les
    # valeurs date (`DateValue`/`DatetimeValue`, qui sont de vrais `Date`) en
    # texte au format français.
    def champ_cell_value(champ)
      value = graphql_champ_value(champ)
      value.is_a?(Date) ? value.to_s : value
    end
```

- [ ] **Step 4 : Lancer les tests**

Run: `bundle exec rspec spec/lib/excel/from_repetitions_spec.rb`
Expected: PASS (2 exemples). Le premier passe déjà avant la bascule (la valeur est encore une chaîne) : c'est voulu, il devient une garde réelle à la Task 4.

- [ ] **Step 5 : Lint puis commit**

```bash
bundle exec rubocop -A app/lib/excel/from_repetitions.rb spec/lib/excel/from_repetitions_spec.rb
bundle exec rake lint
git add app/lib/excel/from_repetitions.rb spec/lib/excel/from_repetitions_spec.rb
git commit -m "refactor(excel): aplatir les valeurs date en texte avant écriture de cellule"
```

---

### Task 4 : Bascule de `graphql_champ_value`

**Files:**
- Modify: `app/lib/datetime_value.rb` (ajout de `#date`)
- Modify: `spec/lib/date_value_spec.rb` (compléter)
- Modify: `app/lib/field_checker.rb:174-175` (branche `DatetimeChamp`/`DateChamp` de `graphql_champ_value`) et `:196-201` (suppression de `date_value`, devenu sans appelant)
- Test: `spec/lib/field_checker_date_spec.rb` (compléter)

**Interfaces:**
- Consomme : `DateValue`, `DatetimeValue` (Task 1).
- Produit : `champ_value(DateChamp) -> DateValue | ''`, `champ_value(DatetimeChamp) -> DatetimeValue | ''`, et `DatetimeValue#date -> DateValue`. La chaîne vide est conservée pour un champ non renseigné (contrat actuel, sur lequel s'appuient `daf/instruction.rb:60` et `champs_to_values`).

- [ ] **Step 1 : Écrire le test de `DatetimeValue#date`**

Dans `spec/lib/date_value_spec.rb`, dans le `RSpec.describe DatetimeValue`, ajouter :

```ruby
  # Contrepartie de l'affichage avec l'heure : un template Sablon peut retomber
  # sur la date seule par «=mon_champ.date» (Sablon fait `public_send` sur la
  # valeur du contexte quand le champ de fusion contient un point).
  it 'expose la date seule, affichable au format français' do
    expect(datetime.date).to be_a(DateValue)
    expect(datetime.date.to_s).to eq('27/07/2026')
  end
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `bundle exec rspec spec/lib/date_value_spec.rb`
Expected: FAIL — `undefined method 'date'` (ou `expected DateTime to be a kind of DateValue` selon ce que Ruby expose).

- [ ] **Step 3 : Implémenter `DatetimeValue#date`**

Dans `app/lib/datetime_value.rb` :

```ruby
  # Date seule, sans l'heure. Utilisable telle quelle dans un template Sablon
  # («=mon_champ.date») ou dans un plugin. Renvoie un `DateValue` et non un
  # `Date` nu, pour que l'affichage reste au format français.
  def date
    DateValue.new(year, month, day)
  end
```

- [ ] **Step 4 : Lancer le test pour vérifier qu'il passe**

Run: `bundle exec rspec spec/lib/date_value_spec.rb`
Expected: PASS (10 exemples)

- [ ] **Step 5 : Ajouter le test de la nouvelle capacité de `champ_value`**

Dans `spec/lib/field_checker_date_spec.rb`, ajouter avant le dernier `end` :

```ruby
  describe 'valeur exploitable par les plugins' do
    it 'rend un objet date comparable et calculable' do
      value = checker.champ_value(champ)
      expect(value).to be_a(Date)
      expect(value).to eq(Date.new(2026, 7, 27))
      expect(value.year).to eq(2026)
    end

    # Changement de sortie assumé : aujourd'hui l'heure est perdue (même branche
    # que DateChamp, format %d/%m/%Y). Voir « Décision » en tête de plan.
    it 'rend un DatetimeValue affichant l’heure pour un champ date-heure' do
      datetime_champ = double('DatetimeChamp', label: 'Horodatage', __typename: 'DatetimeChamp',
                                              string_value: '2026-07-27T09:30:00+10:00')
      value = checker.champ_value(datetime_champ)
      expect(value).to be_a(DatetimeValue)
      expect(value.to_s).to eq('27/07/2026 à 09h30')
      expect(value.date.to_s).to eq('27/07/2026')
    end
  end
```

- [ ] **Step 6 : Lancer le test pour vérifier qu'il échoue**

Run: `bundle exec rspec spec/lib/field_checker_date_spec.rb`
Expected: FAIL — `expected '27/07/2026' to be a kind of Date` (une chaîne est renvoyée).

- [ ] **Step 7 : Écrire l'implémentation**

Dans `app/lib/field_checker.rb`, remplacer la branche de `graphql_champ_value` :

```ruby
    when 'DatetimeChamp', 'DateChamp'
      date_value(champ, '%d/%m/%Y')
```

par :

```ruby
    when 'DateChamp'
      typed_date_value(champ, DateValue)
    when 'DatetimeChamp'
      typed_date_value(champ, DatetimeValue)
```

Supprimer ensuite la méthode `date_value(champ, format)` (`app/lib/field_checker.rb:196-201`) : l'appel ci-dessus était son unique appelant dans tout le dépôt (vérifié par `grep -rn "date_value(" app/ spec/`), elle deviendrait du code mort. Un formatage explicite ponctuel se fait désormais par `champ_value(champ).strftime(...)`. Conserver `raw_date_value`, qui reste utilisé.

Ajouter à la place :

```ruby
  # Valeur date d'un champ sous forme d'objet natif (cf. DateValue) : les plugins
  # peuvent comparer et calculer dessus, l'affichage reste au format français.
  # Chaîne vide si le champ n'est pas renseigné, pour ne pas changer le contrat
  # de `champ_value` (les appelants testent `.blank?` / `.present?`).
  def typed_date_value(champ, klass)
    iso = raw_date_value(champ)
    return '' if iso.blank?

    klass.iso8601(iso)
  rescue Date::Error
    Rails.logger.warn("Date illisible sur le champ #{champ.label} : #{iso.inspect}")
    ''
  end
```

- [ ] **Step 8 : Lancer les tests des deux fichiers, puis la suite complète**

Run: `bundle exec rspec spec/lib/date_value_spec.rb spec/lib/field_checker_date_spec.rb`
Expected: PASS (18 exemples) — dont les 6 tests de caractérisation de la Task 2, **inchangés** : si l'un d'eux casse, la bascule a modifié une sortie visible et il faut corriger l'implémentation, pas le test.

Run: `bundle exec rspec`
Expected: 3 échecs, tous dans `spec/requests/admin/schema_builder_spec.rb` (référence des Global Constraints). Tout autre échec est une régression à corriger avant de committer.

- [ ] **Step 9 : Lint puis commit**

```bash
bundle exec rubocop -A app/lib/field_checker.rb app/lib/datetime_value.rb spec/lib/field_checker_date_spec.rb spec/lib/date_value_spec.rb
bundle exec rake lint
git add app/lib/field_checker.rb app/lib/datetime_value.rb spec/lib/field_checker_date_spec.rb spec/lib/date_value_spec.rb
git commit -F - <<'EOF'
feat(champs): champ_value rend une date native au lieu d'une chaîne

Les plugins peuvent comparer et calculer sur les dates d'un champ sans les
reparser, et l'affichage reste au format français : seul `to_s` de DateValue /
DatetimeValue est francisé, la sérialisation JSON des mutations reste ISO8601.

Les champs date-heure affichent désormais l'heure (`27/07/2026 à 09h30`) :
ils partageaient la branche des DateChamp au format `%d/%m/%Y`, donc l'heure
était perdue. `DatetimeValue#date` permet de retomber sur la date seule,
y compris dans un template Sablon (`«=mon_champ.date»`).

`date_value(champ, format)` est supprimée : son unique appelant était la
branche remplacée.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 5 : Retirer le contournement local de daeth (optionnelle)

`Travail::Daeth#row_champ_value` (introduit par 2664e06) reparse lui-même les dates avec `raw_date_value` + `Date.iso8601` ; après la Task 4, `champ_value` le fait déjà. La branche booléenne doit en revanche **rester** : `champ_value` rend `'Oui'`/`'Non'` pour une case à cocher, deux valeurs vraies, et daeth a besoin d'un booléen pour la rente.

**Décision à prendre avant d'exécuter cette tâche :** le message écrit dans l'annotation « Messages du robot » interpole ces dates (`app/lib/travail/daeth.rb:351`). Il affiche aujourd'hui `valide entre 2024-01-01 et 2025-09-01` ; avec `DateValue` il affichera `valide entre 01/01/2024 et 01/09/2025`. C'est plus lisible pour les agents, mais c'est un changement visible : le faire valider, et ne pas bumper `version` sans accord explicite.

**Files:**
- Modify: `app/lib/travail/daeth.rb:218-232` (`row_champ_value`)
- Modify: `spec/lib/travail/daeth_spec.rb` (attentes de log des contextes COTOREP)

**Interfaces:**
- Consomme : `champ_value` (Task 4).
- Produit : rien de nouveau ; `#disabled_workers` garde le même contrat (`Date`, booléen, `Integer`).

- [ ] **Step 1 : Simplifier `row_champ_value`**

```ruby
    # `champ_value` rend déjà une date native ; il ne reste à traiter que les
    # cases à cocher, dont la valeur affichable (`Oui`/`Non`) est toujours vraie
    # alors que le calcul a besoin du booléen.
    def row_champ_value(champ)
      case champ.__typename
      when 'CheckboxChamp', 'YesNoChamp'
        champ.checked
      else
        champ_value(champ)
      end
    end
```

- [ ] **Step 2 : Lancer les tests de daeth**

Run: `bundle exec rspec spec/lib/travail/daeth_spec.rb`
Expected: les 3 exemples de `#disabled_workers` passent (les dates restent des `Date`, `contract_hours` reste `39`) ; les contextes `with cotorep` échouent sur le format de date du log attendu.

- [ ] **Step 3 : Mettre à jour les attentes de log**

Dans `spec/lib/travail/daeth_spec.rb`, contexte `with cotorep`, remplacer dans `disabled_worker_log` chaque `valide entre AAAA-MM-JJ et AAAA-MM-JJ` par sa forme française, par exemple :

```
2 = Reconnu COTOREP: C, valide entre 01/01/2024 et 01/09/2025, h/sem: 100%  présence annuelle:100.0%
```

Ne toucher qu'aux dates : les taux et les montants ne changent pas.

- [ ] **Step 4 : Lancer les tests**

Run: `bundle exec rspec spec/lib/travail/daeth_spec.rb`
Expected: PASS (11 exemples)

- [ ] **Step 5 : Lint puis commit**

```bash
bundle exec rubocop -A app/lib/travail/daeth.rb spec/lib/travail/daeth_spec.rb
bundle exec rake lint
git add app/lib/travail/daeth.rb spec/lib/travail/daeth_spec.rb
git commit -m "refactor(daeth): s'appuyer sur les dates natives de champ_value"
```

---

## Vérification finale

- [ ] `bundle exec rspec` → 3 échecs pré-existants (`schema_builder_spec`), aucun autre.
- [ ] `bundle exec rake lint` → 0 offense.
- [ ] Relecture ciblée : `grep -rn "champ_value" app/lib | grep -v get_champ_value` — vérifier qu'aucun appelant ne fait d'opération de chaîne (`gsub`, `match?`, `strip`, `downcase`) directement sur le résultat pour un champ date.
- [ ] Test manuel recommandé sur staging avant production : un publipostage contenant une date, et une `conditional_field` branchée sur un champ date, pour confirmer sur pièce que la sortie est inchangée.

## Hors périmètre

- `mes_demarches_to_baserow/data_extractor.rb` et `mes_demarches_to_grist/data_extractor.rb` : ils ont leur propre `get_champ_value` et lisent `champ.date_value` en ISO, ce qui est le bon format pour Baserow et Grist. Ne pas y toucher.
- Les trois autres usages du motif `respond_to?(:value)` (`set_annotation_value.rb:262`, `daf/act_copy_amount.rb:51`, et les deux extracteurs) : revus le 27/07/2026, tous corrects — le fallback n'est atteint que par des types qui répondent réellement à `value`, ou retombe sur `string_value`.
- `Excel::FromRepetitions::FIELD_TYPES` (`app/lib/excel/from_repetitions.rb:8`) liste `DateTimeChamp` alors que le type GraphQL s'appelle `DatetimeChamp` : les champs date-heure sont donc silencieusement exclus de l'export depuis toujours. Bug distinct, préexistant, à traiter séparément — le corriger ici mêlerait un changement de contenu d'export à un plan censé ne rien changer.
- Généraliser `BooleanValue` à `champ_value` (pour que les cases à cocher rendent un booléen natif hors PublipostageV3) : même famille de sujet, mais périmètre distinct, avec des appelants qui comparent explicitement à `'Oui'`. À traiter dans un chantier séparé si le besoin se confirme.
