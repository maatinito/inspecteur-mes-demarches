# Déclaration de sinistre agricole (démarche 3893) — Architecture & devis

- **Date** : 2026-07-21
- **Démarche** : 3893 (ébauche à reprendre)
- **Service** : Service en charge de l'agriculture (dispositif CATANAT — indemnisation des pertes matérielles des professionnels du secteur agricole lors de catastrophes naturelles)
- **Sources** : `storage/projets/DAG/Déclaration de sinistre/` — `Formulaire de déclaration de dégât.docx` (formulaire papier) + `Annexe_2-3.pdf` (barème de calcul des indemnisations)
- **Objet de ce document** : cadrer l'architecture **avant** de toucher au formulaire, et produire un **devis de charge de développement**.

---

## 1. Principe directeur

**Le robot inspecteur est l'unique moteur de calcul.** Le formulaire collecte, il ne calcule pas.

Le **barème vit dans un référentiel Baserow** (« référentiel de Polynésie ») éditable par le service, alimenté dans le formulaire par le mapping de référentiel, et consommé par le plugin de calcul.

### Pourquoi ce choix (débat tranché)
- Le moteur de formules (Dentaku, `formula_calculation_service.rb` côté mes-demarches) sait faire le calcul par ligne et les agrégats `SOMME({Bloc/Champ})`, **mais ne sait pas faire de `SOMME.SI`** (somme conditionnelle). Or les **plafonds sont par catégorie avec cumul multi-lignes** → impossible à appliquer correctement dans le formulaire. Le montant officiel doit donc **de toute façon** être calculé par le robot.
- Faisabilité validée avec l'utilisateur :
  - (a) mapping de référentiel **par ligne dans un bloc répétable** → **OUI**.
  - (b) une formule de ligne peut référencer les champs alimentés par ce mapping → **NON, pas encore**.
- Conséquence : coder le barème *dans les formules* impliquerait de le maintenir deux fois (formules + plugin). On l'évite : **une seule source de vérité, le référentiel**, un seul moteur, le robot.

### Chemin d'évolution (hors périmètre V1)
Proposer au cœur de Mes-Démarches la feature **« une formule peut référencer les colonnes mappées d'un référentiel »**. Le jour où elle est livrée, on ajoutera une estimation temps réel *dans le formulaire* **sans rien refaire**, puisque le barème est déjà dans le référentiel.

### Affichage à l'usager
L'affichage temps réel dans le formulaire n'est **pas possible** aujourd'hui (point b). Il est remplacé par un **message d'estimation** que le robot envoie à l'usager (calcul effectué en `en_construction`).

---

## 2. Flux fonctionnel

```
Usager remplit (3 blocs répétables : cultures / animaux-ruches / équipements)
   │  catégorie = champ referentiel_de_polynesie (mapping → taux, plafond rapatriés)
   ▼
Robot (en_construction) : calcule l'ESTIMÉ + envoie un MESSAGE d'estimation à l'usager
   ▼
Passage en_instruction → CopyOrder gèle la recopie : miroir annotations = « liste retenue »
   ▼
Agent corrige la liste retenue (quantités, refus équipement sans facture…)
   ▼
Robot (en_instruction) : recalcule le montant OFFICIEL sur les annotations
   ▼
Agent appose son VISA (obligatoire)
   ▼
Acceptation → Décompte d'indemnisation (publipostage_v2, .docx/PDF)
```

Le versement de l'indemnité reste **hors Mes-Démarches** (mandatement comptable manuel). Pas de PayZen (c'est l'administration qui verse, pas l'usager qui paie).

---

## 3. Le barème (référentiel « Barème CATANAT »)

Table Baserow avec, par catégorie de moyen de production :

| Colonne | Rôle |
|---|---|
| `categorie` | cultures / vanille / apiculture / animaux / structures |
| `libelle` | libellé de la ligne (ex. « Cultures maraîchères et horticoles ») |
| `unite` | m² / plant / nombre / animal / — |
| `taux_non_bio` | montant à l'unité |
| `taux_bio` | montant à l'unité en bio (+30 %, **sauf porcs** : identique) |
| `plafond_categorie` | plafond max d'aide (cumul multi-lignes de la catégorie) |
| `mode` | `unitaire` (quantité × taux) ou `devis_facture` (100 % du montant devis/facture) |
| `remboursable_sans_facture` | booléen (règle « équipement sans facture = 0 ») |

**Corrections/décisions barème :**
- **Plants forestiers = 10 F/m²** (et non 20 comme lu dans l'Annexe 2/3). Bio = 13 F/m². Plafond 1 000 000.
- Vanille (remise en état, replantation tuteur) et structures/équipements = `mode: devis_facture` (100 % devis/facture, plafonné).
- **Pas de plafond global** par dossier en V1 (éventuelle évolution ultérieure).

Contenu de référence (Annexe 2/3, à saisir dans Baserow) :
- **Cultures (m²)** : maraîchères 20, vivrières 20, vergers 25, cocotiers 10, cannes/cacao/café 10, bananiers/fei 26, **forestiers 10** ; bio +30 % ; plafonds 1 000 000–1 500 000.
- **Vanille** : ombrière 2 000 F/m² (bio 2 500) ; travaux remise en état & tuteur = 100 % devis ; plafonds 500 000–1 000 000.
- **Apiculture** : ruche+colonie 10 000 F (bio 13 000) ; plafond 500 000.
- **Animaux (par tête)** : poules/poulets 500, porcelets 5 000 (bio 6 500), porcs reproducteurs 50 000 (bio =), porcs charcutiers 30 000 (bio =), bovins reproducteurs 100 000 (bio 130 000) ; plafonds 600 000–2 000 000.
- **Structures/équipements** : serres, tracteurs/engins lourds, motoculteurs, aménagements, irrigation = 100 % devis/facture ; plafonds 1 000 000–2 000 000.

---

## 4. Architecture par composant

### 4.1 Référentiel barème (Baserow)
Table + saisie des ~25 lignes + configuration du mapping référentiel dans le formulaire (MCP `configurer_referentiel_mapping`), pour rapatrier `taux_*` et `plafond_categorie` dans des champs (cachés) de chaque ligne.

### 4.2 Formulaire (démarche 3893)
Reconstruit via le MCP mes-demarches à partir du formulaire papier :
- **En-tête** : date et durée du sinistre.
- **A/ Identité** : nom/prénom, date de naissance, adresses postale et géographique de l'exploitation (archipel/île/commune/section), téléphones ; si personne morale : dénomination, N° Tahiti, titre du représentant.
- **B/ Moyens endommagés** : 4 oui/non (cultures / animaux / bâtiments / matériel) → **conditions d'affichage** des blocs D correspondants.
- **C/ Assurance** : compagnie, n° police, période, éléments couverts, garanties souscrites.
- **D/ 3 blocs répétables** :
  - Cultures : catégorie (référentiel), quantité (m²/plants), bio (oui/non), description, PJ.
  - Animaux/ruches : catégorie (référentiel), nombre, bio, description, PJ.
  - Équipements/bâtiments : catégorie (référentiel), date d'achat, montant neuf, estimation coût, **PJ facture/devis** (obligatoire pour remboursement), observation.
- Nettoyage des options parasites (`Fromage`/`Dessert` sur « Mandataire ? »), conditions mandataire / personne morale.

### 4.3 Miroir agent + recopie (`Daf::CopyOrder`)
`app/lib/daf/copy_order.rb` fait déjà : lecture d'un bloc source usager (`param_field`) **ou** annotation (`param_annotation`), allocation de lignes dans un **bloc d'annotations répétable** (`SetAnnotationValue.allocate_blocks`), copie champs texte **et** pièces jointes (dédup par checksum). N'écrit que si la valeur diffère.

**Adaptations à prévoir :**
1. **Typage** : `extract_row_data` produit des String ; nos lignes portent des numériques et une **sélection de référentiel**. Vérifier/étendre que `SetAnnotationValue.raw_set_value` accepte ces types.
2. **Protection des corrections agent** : recopie active en `en_construction`, **gelée** dès `en_instruction` (l'agent prend la main) + case à cocher **« Bloquer la recopie » (`bloquer_si`)** pour resync volontaire. Sans ce gel, un cycle d'inspection écraserait les corrections de l'agent.

### 4.4 Plugin de calcul du montant (`FieldChecker`)
Nouveau checker qui :
- lit le référentiel barème + les lignes (usager en construction, annotations en instruction) ;
- calcule **par ligne** (`unitaire` : quantité × taux selon bio ; `devis_facture` : montant saisi) ;
- applique les **plafonds par catégorie en cumulant les lignes** d'une même catégorie (ce que le formulaire ne peut pas faire) ;
- applique la règle **« équipement sans facture = 0 »** ;
- écrit le **montant estimé** (en construction, sur champs usager) et le **montant officiel** (en instruction, sur annotations) ;
- déclenche l'envoi du **message d'estimation** à l'usager.

### 4.5 Visa (obligatoire)
Annotation de **visa agent** ; le décompte n'est produit/émis qu'**après** apposition du visa.

### 4.6 Décompte d'indemnisation (`publipostage_v2`)
Modèle `.docx` avec **répétitions** (les 3 tableaux + totaux par catégorie + total général), généré à l'acceptation, après visa.

---

## 5. Devis (charge de développement)

| Lot | Contenu | Charge |
|---|---|---|
| **1. Référentiel barème** | Table Baserow + saisie ~25 lignes + mapping référentiel dans le formulaire | ~1 j |
| **2. Formulaire complet (3893)** | Sections A/B/C/D via MCP, 3 blocs répétables, conditions, nettoyage | ~1,5–2 j |
| **3. Miroir agent + recopie** | Blocs annotations + config `CopyOrder` + adaptations typage & gel/`bloquer_si` + tests | ~2–3 j |
| **4. Plugin calcul montant** | Calcul par ligne + plafonds catégorie cumulés + bio + règle sans-facture + estimé/officiel + message d'estimation + tests | ~2,5–3 j |
| **5. Visa + décompte publipostage** | Annotation visa + gate d'émission + modèle `.docx` (3 tableaux + totaux) via `publipostage_v2` + test | ~2–2,5 j |
| **6. Recette live + staging** | Bout-en-bout sur bac à sable, déploiement staging | ~1 j |
| — | *Demande d'évolution plateforme « formule ↔ mapping référentiel » (log)* | *~0,25 j* |
| *(opt.)* | *Estimation temps réel dans le formulaire, une fois l'évolution plateforme livrée* | *~1 j, à part* |

**Total V1 : ~10–12,5 jours.**

---

## 6. Hypothèses & risques
- Mapping référentiel **par ligne de bloc répétable** : confirmé faisable.
- Formule ↔ colonnes mappées : **indisponible** aujourd'hui → « robot calcule » assumé.
- Typage `CopyOrder` sur numériques/référentiel : à valider tôt (peut ajouter ~0,5 j si `raw_set_value` doit être étendu).
- Fréquence des cycles d'inspection = latence de l'estimation et de la recopie (acceptable pour un devis d'indemnisation).

## 7. Décisions arrêtées
- Périmètre = **toute l'architecture (5 lots)**.
- Barème = **référentiel Baserow** (source unique), consommé par le robot.
- Sortie = **décompte publipostage seul** (versement hors MD).
- **Plants forestiers = 10 F/m²**.
- **Visa agent obligatoire** avant décompte.
- **Pas de plafond global** en V1.

## 8. Points restant à confirmer avec le service (non bloquants)
- Aucun en suspens critique. Un plafond global éventuel sera traité comme évolution si le besoin apparaît.

## 9. Prochaine étape
Plan d'implémentation détaillé (skill `writing-plans`). Ordre recommandé :
1. Lot 1 (référentiel) — débloque tout le reste.
2. Lot 2 (formulaire).
3. Lot 3 (recopie) — valider le typage `CopyOrder` en premier.
4. Lot 4 (plugin calcul).
5. Lot 5 (visa + décompte).
6. Lot 6 (recette + staging).
