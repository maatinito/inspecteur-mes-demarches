# frozen_string_literal: true

module Travail
  # Répartition des travailleurs handicapés par statut et par catégorie, pour le
  # bilan social des administrations.
  #
  # Tâche distincte de Travail::Daeth, dont elle reprend le calcul par
  # travailleur sans rien recalculer d'autre : elle n'écrit qu'une annotation
  # texte et peut donc tourner sur des dossiers clos, où les montants ne doivent
  # plus bouger. La démarche du privé, qui partage Travail::Daeth, ne l'utilise
  # pas.
  #
  # L'annotation porte deux blocs au format fixe, découpés ensuite par des
  # colonnes formule côté Grist — ne pas en changer la forme sans les adapter :
  #
  #   ETP ; A ; B ; C ; D        prorata de temps de présence
  #   FPT ; 1 ; 1 ; 0 ; 0
  #   …
  #   Non classé ; 0
  #
  #   Unités ; A ; B ; C ; D     même prorata, pondéré (COTOREP C = 2)
  #   …
  #
  # Un travailleur qui vaut 0 unité (accident du travail sans rente, IPP
  # insuffisant) n'est pas bénéficiaire : il est absent des deux blocs.
  class DaethRepartition < Daeth
    STATUTS = ['FPT', 'FPT stagiaire', 'ANFA', 'ANT'].freeze
    CATEGORIES = %w[A B C D].freeze
    # Préfixe du cadre d'emplois (« A - Ingénieur », « AN3 - CC3 ») → colonne.
    CATEGORIE_PAR_PREFIXE = {
      'A' => 'A', 'AN1' => 'A',
      'B' => 'B', 'AN2' => 'B',
      'C' => 'C', 'AN3' => 'C',
      'D' => 'D', 'AN4' => 'D', 'AN5' => 'D'
    }.freeze
    NON_CLASSE = 'Non classé'
    SEPARATEUR = ' ; '
    # Début du message levé par SetAnnotationValue.set_value.
    ANNOTATION_ABSENTE = 'Unable to find annotation'

    def required_fields
      super - ASSESSMENT_FIELDS + %i[champ_categorie annotation_details]
    end

    private

    def compute_and_save
      @year = declared_year(nil)
      etp, unites = repartition
      save_annotation(@params[:annotation_details], [bloc('ETP', etp), bloc('Unités', unites)].join("\n\n"))
    rescue RuntimeError => e
      # Un dossier clos resté sur une ancienne révision n'a pas l'annotation :
      # il ne doit pas interrompre le traitement des autres dossiers. Toute
      # autre erreur (réseau, API) remonte, pour que le dossier soit rejoué.
      raise unless e.message.start_with?(ANNOTATION_ABSENTE)

      Rails.logger.error("DaethRepartition: dossier #{@dossier.number} non traité : #{e.message}")
    end

    def disabled_worker_attributes(fields)
      super.merge(category: fields[@params[:champ_categorie]])
    end

    # Deux grilles { [statut, catégorie] => somme }, la clé NON_CLASSE recevant
    # les travailleurs dont le statut ou le cadre d'emplois n'est pas reconnu.
    def repartition
      etp = Hash.new(0.0)
      unites = Hash.new(0.0)
      disabled_workers.each do |worker|
        next if worker[:contract_type] == CONTRACT_SITH

        poids, = payload(worker)
        next unless poids.positive?

        presence = (compute_weekly_presence_rate(worker) * compute_year_presence_rate(worker)).round(3)
        case_grille = case_de(worker)
        etp[case_grille] += presence
        unites[case_grille] += (poids * presence).round(3)
      end
      [etp, unites]
    end

    def case_de(worker)
      statut = statut_de(worker[:contract_type])
      categorie = CATEGORIE_PAR_PREFIXE[worker[:category].to_s.split(' - ').first.to_s.strip]
      statut && categorie ? [statut, categorie] : NON_CLASSE
    end

    # Le formulaire propose « ANFA, PNNIM, ENIM, DI, SR, AVOC » : tout ce qui
    # commence par ANFA va sur la ligne ANFA.
    def statut_de(valeur)
      valeur = valeur.to_s.strip
      return 'ANFA' if valeur.start_with?('ANFA')

      STATUTS.find { |statut| statut == valeur }
    end

    def bloc(titre, grille)
      lignes = STATUTS.map do |statut|
        [statut, *CATEGORIES.map { |categorie| nombre(grille[[statut, categorie]]) }].join(SEPARATEUR)
      end
      [[titre, *CATEGORIES].join(SEPARATEUR), *lignes, [NON_CLASSE, nombre(grille[NON_CLASSE])].join(SEPARATEUR)].join("\n")
    end

    # Virgule décimale, trois décimales au plus, sans zéros de fin.
    def nombre(valeur)
      arrondi = valeur.round(3)
      (arrondi == arrondi.to_i ? arrondi.to_i : arrondi).to_s.tr('.', ',')
    end
  end
end
