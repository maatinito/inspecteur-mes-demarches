# frozen_string_literal: true

module Dbs
  # Calcul de publipostage du laissez-passer poussins (démarche 3899) : prépare ce que le gabarit ne sait pas
  # assembler seul, parce que cela croise plusieurs sources du dossier.
  #   Destinataires            « Nom (élevage) ; … » — bloc des éleveurs + importateur qui isole chez lui
  #   Certificats d'isolement  une référence numérotée par engagement reçu, à partir de 6/ (les références 1 à 5
  #                            du modèle sont fixes) : { rang, numero, date, site, fin } ; le n° est celui du
  #                            dossier d'engagement, l'élevage est retrouvé par le courriel d'attribution
  #   Articles                 lignes du tableau : une par certificat sanitaire relevé par l'agent. Dans le cas
  #                            courant (un seul certificat), l'agent ne saisit ni le nombre ni la désignation : ils
  #                            viennent des champs de l'importateur. Sans certificat relevé, une ligne quand même.
  #   LTA                      numéros de LTA des certificats, sans doublon
  #   Pays d'origine           Nouvelle-Zélande, ou le pays saisi pour « Autre pays »
  class ReferencesLaissezPasser < FieldChecker
    include Dbs::EleveursDuLot

    PREMIER_RANG = 6

    DEFAUTS = {
      # bloc des éleveurs
      nom_eleveur: "Nom et Prénom de l'éleveur", email_eleveur: "Email de l'éleveur",
      telephone_eleveur: "Téléphone de l'éleveur", quantite_eleveur: 'Quantité de poussins',
      nom_elevage: "Nom de l'élevage", importateur_eleveur: nil,
      # champs de l'importateur
      quantite_totale: 'Quantité totale', destination: 'Destination des poussins',
      races: ['Race ponte', 'Race chair'], provenance: 'Provenance', autre_pays: 'Autre pays',
      pays_provenance: 'Pays de provenance',
      # bloc des certificats sanitaires (annotations)
      designation: 'Désignation des poussins', nombre: 'Nombre de poussins',
      numero_certificat: 'Numéro du certificat sanitaire', numero_lta: 'Numéro de LTA', colis: 'Nombre de colis'
    }.freeze

    def version
      super + 2
    end

    def required_fields
      super + %i[eleveurs engagements_recus certificats]
    end

    def authorized_fields
      super + DEFAUTS.keys
    end

    def initialize(params)
      super
      @cfg = DEFAUTS.merge((required_fields + DEFAUTS.keys).index_with { |k| @params[k] }.compact)
      @cfg[:importateur_eleveur] = @cfg[:importateur_eleveur].to_h.deep_symbolize_keys if @cfg[:importateur_eleveur].present?
    end

    def process_row(dossier, output)
      eleveurs = eleveurs_du_lot(dossier, @cfg)
      output['Destinataires'] = eleveurs.map { |e| "#{e[:nom]} (#{elevage(e, dossier)})" }.join(' ; ')
      output["Certificats d'isolement"] = certificats_isolement(dossier, eleveurs)
      pays = pays_origine(dossier)
      output["Pays d'origine"] = pays
      lignes = lignes_certificats(dossier)
      output['Articles'] = articles(dossier, lignes, pays)
      output['LTA'] = lignes.filter_map { |l| l[@cfg[:numero_lta]].presence }.uniq.join(', ')
    end

    private

    def certificats_isolement(dossier, eleveurs)
      engagements = ListeEngagements.parse_recus(texte_annotation(dossier, @cfg[:engagements_recus])).sort_by(&:numero)
      engagements.each_with_index.map do |e, i|
        { 'rang' => PREMIER_RANG + i, 'numero' => e.numero, 'date' => e.date.strftime('%d/%m/%Y'),
          'site' => site(e, eleveurs, dossier), 'fin' => i < engagements.size - 1 ? ' ;' : '' }
      end
    end

    def articles(dossier, lignes, pays)
      lignes = [{}] if lignes.empty?
      lignes.map do |l|
        { 'nombre' => l[@cfg[:nombre]].presence || valeur(dossier, @cfg[:quantite_totale]),
          'designation' => l[@cfg[:designation]].presence || designation_declaree(dossier),
          'pays' => pays, 'certificat' => l[@cfg[:numero_certificat]].to_s, 'colis' => l[@cfg[:colis]].to_s }
      end
    end

    def designation_declaree(dossier)
      race = Array(@cfg[:races]).map { |libelle| valeur(dossier, libelle) }.find(&:present?)
      ["poussins de #{valeur(dossier, @cfg[:destination]).downcase}", race.presence && "de race #{race}"].compact.join(' ')
    end

    def pays_origine(dossier)
      provenance = valeur(dossier, @cfg[:provenance])
      provenance == @cfg[:autre_pays] ? valeur(dossier, @cfg[:pays_provenance]) : provenance
    end

    def elevage(eleveur, dossier)
      eleveur[:valeurs][@cfg[:nom_elevage]].presence || raison_sociale(dossier)
    end

    def site(engagement, eleveurs, dossier)
      eleveur = eleveurs.find { |e| e[:email].present? && e[:email] == engagement.email }
      eleveur ? elevage(eleveur, dossier) : engagement.nom
    end

    def raison_sociale(dossier)
      demandeur = dossier.demandeur
      demandeur.respond_to?(:entreprise) ? demandeur.entreprise&.raison_sociale.to_s : ''
    end

    # Valeur texte d'un champ ou d'une annotation, par libellé.
    def valeur(dossier, libelle)
      champs_to_values(object_field_values(dossier, libelle, log_empty: false)).first.to_s.strip
    end

    def texte_annotation(dossier, nom)
      champ_value(dossier_annotations(dossier, nom, warn_if_empty: false)&.first).to_s
    end

    # Lignes du bloc des certificats : { libellé du sous-champ => valeur texte }.
    def lignes_certificats(dossier)
      bloc = dossier_annotations(dossier, @cfg[:certificats], warn_if_empty: false)&.first
      (bloc&.rows || []).map { |row| row.champs.to_h { |c| [c.label, champ_value(c).to_s.strip] } }
    end
  end
end
