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
  # L'annotation porte, par statut, deux mesures côte à côte au format fixe,
  # découpées ensuite par des colonnes formule côté Grist — ne pas en changer la
  # forme sans les adapter :
  #
  #   Statut ; ETP A ; B ; C ; D | Unités A ; B ; C ; D
  #   FPT ; 2 ; 2,901 ; 2,732 ; 7 | 2 ; 2,901 ; 2,732 ; 8
  #   …
  #   Non classé ; 0 | 0
  #
  # ETP = prorata de temps de présence ; unités = même prorata, pondéré
  # (COTOREP C = 2). Six lignes seulement : l'agent lit l'annotation à l'écran.
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
    SEPARATEUR_MESURES = ' | '
    ENTETE = 'Statut ; ETP A ; B ; C ; D | Unités A ; B ; C ; D'
    # Début du message levé par SetAnnotationValue.set_value.
    ANNOTATION_ABSENTE = 'Unable to find annotation'
    ETATS_CLOS = %w[accepte refuse sans_suite].freeze

    def required_fields
      super - ASSESSMENT_FIELDS + %i[champ_categorie annotation_details]
    end

    private

    def compute_and_save
      @year = declared_year(nil)
      etp, unites = repartition
      save_annotation(@params[:annotation_details], texte(etp, unites))
    rescue RuntimeError => e
      # Un dossier clos resté sur une ancienne révision n'a pas l'annotation :
      # il ne doit pas interrompre le traitement des autres dossiers. Sur un
      # dossier encore ouvert, la même absence est une erreur de configuration
      # (libellé mal saisi) et doit remonter, comme toute autre erreur.
      raise unless annotation_absente_sur_dossier_clos?(e)

      Rails.logger.error("DaethRepartition: dossier #{@dossier.number} non traité : #{e.message}")
    end

    def annotation_absente_sur_dossier_clos?(erreur)
      erreur.message.start_with?(ANNOTATION_ABSENTE) && ETATS_CLOS.include?(@dossier.state)
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

        # Une date de sortie antérieure à la date d'entrée donne un taux
        # négatif : borné à zéro pour ne pas retrancher d'une case.
        hebdo = compute_weekly_presence_rate(worker)
        annuel = [compute_year_presence_rate(worker), 0].max
        case_grille = case_de(worker)
        etp[case_grille] += (hebdo * annuel).round(3)
        # Un seul arrondi, dans l'ordre de Daeth#disabled_worker_fte : la somme
        # des unités doit retomber sur « ETP Bénéficiaires ».
        unites[case_grille] += (poids * hebdo * annuel).round(3)
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

    def texte(etp, unites)
      lignes = STATUTS.map do |statut|
        "#{statut}#{SEPARATEUR}#{valeurs(etp, statut)}#{SEPARATEUR_MESURES}#{valeurs(unites, statut)}"
      end
      [ENTETE, *lignes, "#{NON_CLASSE}#{SEPARATEUR}#{nombre(etp[NON_CLASSE])}#{SEPARATEUR_MESURES}#{nombre(unites[NON_CLASSE])}"].join("\n")
    end

    def valeurs(grille, statut)
      CATEGORIES.map { |categorie| nombre(grille[[statut, categorie]]) }.join(SEPARATEUR)
    end

    # Virgule décimale, trois décimales au plus, sans zéros de fin.
    def nombre(valeur)
      arrondi = valeur.round(3)
      (arrondi == arrondi.to_i ? arrondi.to_i : arrondi).to_s.tr('.', ',')
    end
  end
end
