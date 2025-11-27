# frozen_string_literal: true

class DenominationDemandeur < FieldChecker
  def version
    super + 2
  end

  def required_fields
    super + %i[annotation_cible]
  end

  def authorized_fields
    super + %i[champ_source]
  end

  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    # Déterminer la source (demandeur du dossier ou champ Numéro TAHITI)
    etablissement = if @params[:champ_source].present?
                      param_field(:champ_source)&.etablissement
                    else
                      @dossier.demandeur
                    end

    # Générer la dénomination grammaticale
    denomination = generate_denomination(etablissement)

    if denomination.present?
      actual_value = param_annotation(:annotation_cible)&.value
      if actual_value.blank?
        modified = SetAnnotationValue.set_value(dossier, demarche.instructeur, @params[:annotation_cible], denomination)
        dossier_updated(dossier) if modified
      else
        Rails.logger.warn("dénomination already set to #{actual_value}")
      end
    else
      Rails.logger.warn("Unable to generate denomination for dossier #{dossier.number}")
    end
  end

  private

  def generate_denomination(entity)
    return nil if entity.nil?

    case entity.__typename
    when 'PersonnePhysique'
      generate_personne_physique(entity)
    when 'PersonneMorale'
      generate_personne_morale(entity)
    when 'Etablissement'
      generate_from_etablissement(entity)
    else
      Rails.logger.warn("Unknown entity type: #{entity.__typename}")
      nil
    end
  end

  def generate_personne_physique(personne)
    # Format: civilite prenom nom
    civilite = normalize_civilite(personne.civilite.to_s)
    prenom = personne.prenom || ''
    nom = personne.nom || ''

    parts = [civilite, prenom, nom].map(&:strip).reject(&:blank?)
    parts.join(' ')
  end

  def normalize_civilite(civilite)
    case civilite.strip
    when 'M.', 'M'
      'Monsieur'
    when 'Mme', 'Mme.'
      'Madame'
    else
      civilite
    end
  end

  def generate_personne_morale(personne)
    forme_juridique = personne.entreprise&.forme_juridique
    raison_sociale = personne.entreprise&.raison_sociale

    return nil if forme_juridique.blank? || raison_sociale.blank?

    article_type = legal_form_mapping[forme_juridique]

    if article_type.present?
      "#{article_type} #{raison_sociale}"
    else
      Rails.logger.warn("Forme juridique inconnue: #{forme_juridique}")
      raison_sociale
    end
  end

  def generate_from_etablissement(etablissement)
    # Un établissement a directement un attribut entreprise
    forme_juridique = etablissement.entreprise&.forme_juridique
    raison_sociale = etablissement.entreprise&.raison_sociale

    return nil if forme_juridique.blank? || raison_sociale.blank?

    article_type = legal_form_mapping[forme_juridique]

    if article_type.present?
      "#{article_type} #{raison_sociale}"
    else
      Rails.logger.warn("Forme juridique inconnue: #{forme_juridique}")
      raison_sociale
    end
  end

  # rubocop:disable Metrics/MethodLength
  def legal_form_mapping
    {
      # Personnes physiques
      'Artisan-commerçant' => "l'entreprise",
      'Commerçant' => "l'entreprise",
      'Artisan' => "l'entreprise d'artisanat",
      'Officier public ou ministériel' => "l'officier public ou ministériel",
      'Profession libérale' => "l'entreprise de",
      'Exploitant agricole' => "l'entreprise d'exploitation agricole",
      'Agent commercial' => "l'entreprise individuelle de",
      'Auto-entrepreneur' => "l'entreprise individuelle de",
      'Personne physique' => "l'entreprise individuelle de",

      # Groupements sans personnalité morale
      'Indivision' => "l'indivision",
      'Société de Fait' => 'la société de fait',
      'Société en Participations' => 'la société en participations',
      'Fiducie' => 'la fiducie',
      'Paroisse hors zone concordataire' => 'la paroisse',
      'Autre groupement de droit privé non doté de la personnalité morale' => 'le groupement de droit privé',

      # Personnes morales de droit étranger
      'Personne morale de droit étranger immatriculée au RCS' => 'la personne morale de droit étranger',
      'Personne morale de droit étranger non immatriculée au RCS' => 'la personne morale de droit étranger',

      # Établissements publics
      'Etablissement Public ou régie à caractère industriel ou commercial (dont E.P.I.C.)' => "l'établissement public",

      # Sociétés commerciales
      'Autre société coopérative' => 'la société coopérative',
      'Société en Nom Collectif ou S.N.C.' => 'la S.N.C.',
      'Société en Commandite' => 'la société en commandite',
      'Société A Responsabilité Limitée ou S.A.R.L.' => 'la S.A.R.L.',
      'SARL unipersonnelle (dont E.U.R.L.)' => "l'E.U.R.L.",
      "Société Anonyme à Conseil d'Administration" => 'la S.A.',
      'Société Anonyme à Directoire (dont S.A.E.M.)' => 'la S.A.',
      'Société par Actions Simplifiées ou S.A.S.' => 'la S.A.S.',
      'Société européenne' => 'la société européenne',

      # Institutions financières et économiques
      "Caisse d'Epargne et de Prévoyance" => "la Caisse d'Epargne et de Prévoyance",
      "Groupement d'Intérêt Economique ou G.I.E." => 'le G.I.E.',
      'Société Coopérative Agricole' => 'la société coopérative agricole',
      "Société non commerciale d'Assurances" => "la société d'assurances",

      # Sociétés civiles
      'Société Civile Non Immobilière' => 'la société civile',
      'Société Civile Immobilière (SCI)' => 'la S.C.I.',

      # Autres personnes privées
      'Autres personnes de droit privé inscrites au registre du commerce et des sociétés' => 'la personne de droit privé',

      # Administrations publiques
      "Administration de l'Etat" => "l'administration de l'État",
      'Ministere, service et institution de la collectivité territoriale' => 'le service de la collectivité territoriale',
      'Etablissement Public Administatif de la collectivité territoriale' => "l'établissement public administratif",
      'Administrations Communales' => "l'administration communale",
      'Syndicats de Communes' => 'le syndicat de communes',
      'Autre personne morale de droit public administratif' => 'la personne morale de droit public',

      # Organismes sociaux et professionnels
      'Organisme gérant un régime de protection sociale à adhésion obligatoire' => "l'organisme de protection sociale",
      'Organisme Mutualiste' => "l'organisme mutualiste",
      "Comité d'Entreprise" => "le comité d'entreprise",
      'Organisme Professionnel' => "l'organisme professionnel",
      'Organisme de retraite à adhésion non obligatoire' => "l'organisme de retraite",
      'Syndicat de Propriétaires' => 'le syndicat de propriétaires',

      # Associations et fondations
      'Association de loi 1901 ou assimilé' => "l'association",
      'Fondation' => 'la fondation',
      'Autre personne morale de droit privé' => 'la personne morale de droit privé'
    }
  end
  # rubocop:enable Metrics/MethodLength
end
