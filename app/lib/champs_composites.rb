# frozen_string_literal: true

# Sous-colonnes des champs composites (référentiel de Polynésie, N° Tahiti,
# commune, N° DN) pour la synchronisation vers Grist et Baserow.
#
# Une colonne cible nommée « <libellé du champ> – <sous-colonne> » reçoit la
# sous-valeur : c'est la convention des colonnes du tableau instructeur de
# Mes-Démarches (« N° TAHITI – Entreprise raison sociale »). Le tiret simple est
# accepté, le demi-cadratin ne se tapant pas au clavier.
#
# Partagé par les deux moteurs (parité Baserow/Grist) : ce module rapproche et
# lit les valeurs brutes, chaque extracteur les convertit selon le type de sa
# colonne cible avec les conversions ci-dessous.
module ChampsComposites
  SEPARATEURS = [' – ', ' - '].freeze

  # Sous-colonne inconnue du champ (faute de frappe, colonne de référentiel
  # retirée) : la cellule n'est pas touchée, à la différence d'un nil qui la vide.
  ABSENTE = :absente

  SIRET = {
    'entreprise raison sociale' => ->(e) { e.entreprise&.raison_sociale },
    'entreprise nom commercial' => ->(e) { e.entreprise&.nom_commercial },
    'entreprise forme juridique' => ->(e) { e.entreprise&.forme_juridique },
    'entreprise siren' => ->(e) { e.entreprise&.siren },
    'libelle naf' => lambda(&:libelle_naf),
    'etablissement naf' => lambda(&:naf),
    'etablissement adresse' => ->(e) { e.address&.label }
  }.freeze

  COMMUNE = {
    'commune' => lambda(&:name),
    'code postal' => lambda(&:postal_code),
    'ile' => lambda(&:island),
    'archipel' => lambda(&:archipelago)
  }.freeze

  NUMERO_DN = {
    'date de naissance' => lambda(&:date_de_naissance),
    'numero dn' => lambda(&:numero_dn)
  }.freeze

  TYPES = %w[ReferentielDePolynesieChamp SiretChamp CommuneDePolynesieChamp CodePostalDePolynesieChamp
             NumeroDnChamp].freeze

  BOOLEENS = { 'vrai' => true, 'oui' => true, 'true' => true, '1' => true,
               'faux' => false, 'non' => false, 'false' => false, '0' => false }.freeze

  module_function

  def composite?(champ)
    TYPES.include?(champ.__typename)
  end

  # Rapproche des libellés de colonnes cible des champs composites d'un même
  # niveau (dossier ou ligne de bloc).
  # Retourne { libellé de colonne => [champ, sous-colonne] }.
  def rapprocher(libelles_colonnes, champs)
    composites = champs.select { |c| composite?(c) }.index_by(&:label)
    return {} if composites.empty?

    libelles_champs = champs.to_set(&:label)
    libelles_colonnes.each_with_object({}) do |colonne, result|
      # Une colonne qui porte exactement le libellé d'un champ reçoit le champ entier.
      next if libelles_champs.include?(colonne)

      libelle, sous_colonne = decouper(colonne, composites.keys)
      result[colonne] = [composites[libelle], sous_colonne] if libelle
    end
  end

  # Coupe au séparateur le plus à droite dont la partie gauche est un libellé de
  # champ composite : retient ainsi le libellé le plus long (« Rubrique - ICPE »).
  def decouper(colonne, libelles)
    positions = SEPARATEURS.flat_map do |separateur|
      colonne.to_enum(:scan, separateur).map { [Regexp.last_match.begin(0), separateur] }
    end
    positions.sort_by { |index, _| -index }.each do |index, separateur|
      libelle = colonne[0...index]
      return [libelle, colonne[(index + separateur.length)..]] if libelles.include?(libelle)
    end
    nil
  end

  # Valeur brute d'une sous-colonne, nil si le champ est vide, ABSENTE si la
  # sous-colonne n'existe pas pour ce champ.
  def valeur(champ, sous_colonne)
    cle = normaliser(sous_colonne)
    case champ.__typename
    when 'ReferentielDePolynesieChamp' then valeur_referentiel(champ, cle)
    when 'SiretChamp' then lire(SIRET, cle, champ.etablissement)
    when 'CommuneDePolynesieChamp', 'CodePostalDePolynesieChamp' then lire(COMMUNE, cle, champ.commune)
    when 'NumeroDnChamp' then lire(NUMERO_DN, cle, champ)
    else ABSENTE
    end
  end

  def valeur_referentiel(champ, cle)
    return nil if champ.string_value.blank?

    colonne = champ.columns.find { |c| normaliser(c.name) == cle }
    colonne ? colonne.value : ABSENTE
  end

  def lire(lecteurs, cle, source)
    lecteur = lecteurs[cle]
    return ABSENTE unless lecteur
    return nil if source.nil?

    lecteur.call(source)
  end

  def normaliser(texte)
    I18n.transliterate(texte.to_s).downcase.squish
  end

  # --- Conversions (lèvent ArgumentError sur une valeur inconvertible) -------

  def en_date(valeur)
    return valeur.to_date if valeur.respond_to?(:to_date) && !valeur.is_a?(String)

    texte = valeur.to_s.strip
    return Date.strptime(texte, '%d/%m/%Y') if texte.match?(%r{\A\d{1,2}/\d{1,2}/\d{4}\z})

    Date.iso8601(texte)
  rescue Date::Error
    raise ArgumentError, "date illisible : #{valeur.inspect}"
  end

  def en_nombre(valeur)
    return valeur if valeur.is_a?(Numeric)

    texte = valeur.to_s.gsub(/[[:space:]]/, '').tr(',', '.')
    nombre = Float(texte)
    (nombre % 1).zero? ? nombre.to_i : nombre
  rescue TypeError
    raise ArgumentError, "nombre illisible : #{valeur.inspect}"
  end

  def en_booleen(valeur)
    return valeur if [true, false].include?(valeur)

    BOOLEENS.fetch(normaliser(valeur)) { raise ArgumentError, "booléen illisible : #{valeur.inspect}" }
  end
end
