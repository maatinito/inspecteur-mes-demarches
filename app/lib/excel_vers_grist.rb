# frozen_string_literal: true

require_relative 'excel/sheet_reader'
require_relative 'mes_demarches_to_grist/grist_ref'
require_relative 'mes_demarches_to_grist/ligne_upserter'

# Recopie les lignes d'un Excel joint au dossier vers une table Grist liée.
#
# Pendant « source Excel » de la synchro des blocs répétables : même cible (une
# table liée à la table dossier), même clé d'upsert (Dossier, Ligne), mais les
# lignes viennent d'un fichier au lieu d'un bloc natif.
#
# Le fichier est lu directement depuis Mes-Démarches, et non depuis la copie
# stockée dans Grist : le traitement ne dépend donc pas de la recopie préalable
# de la pièce jointe.
#
# Configuration YAML : cf. docs/superpowers/specs/2026-06-19-excel-vers-grist-design.md §5
class ExcelVersGrist < FieldChecker
  EXTENSION = '.xlsx'

  # Valeur par défaut de la colonne d'empreinte : marque une ligne « à traiter ».
  # Procédé repris du document pesticides, où la colonne excel_checksum porte
  # cette formule de défaut — toute ligne créée entre ainsi d'office dans l'état
  # à traiter, sans code de rattrapage.
  SENTINELLE_A_TRAITER = '-'
  COLONNE_EMPREINTE_DEFAUT = 'excel_checksum'

  # Retour de recopier_lignes signalant qu'aucune ligne n'était exploitable, à
  # distinguer d'un zéro légitime : voir recopier_lignes.
  AUCUNE_LIGNE_EXPLOITABLE = -1

  # Types acceptés dans le mapping YAML, traduits en types de colonnes Grist.
  TYPES_YAML = {
    'text' => 'Text', 'numeric' => 'Numeric', 'int' => 'Int',
    'date' => 'Date', 'datetime' => 'DateTime:UTC', 'bool' => 'Bool',
    'choice' => 'Choice'
  }.freeze

  def version
    super + 1
  end

  def required_fields
    super + %i[champ grist]
  end

  def authorized_fields
    super + %i[feuille ligne_entete colonnes options]
  end

  def initialize(*args)
    super

    @errors << "Configuration 'grist.doc_id' manquante sur excel_vers_grist" unless @params[:grist]&.[]('doc_id')
    @errors << "Configuration 'grist.table_id' manquante sur excel_vers_grist" unless @params[:grist]&.[]('table_id')
  end

  # Messages métier accumulés pendant le traitement (fichier illisible, colonne
  # source absente, conflit de type…). Rendus visibles dans Grist par
  # ecrire_erreurs quand la configuration désigne une colonne d'erreurs.
  def erreurs_metier
    @erreurs_metier ||= []
  end

  def process(demarche, dossier)
    super
    @erreurs_metier = []
    return unless must_check?(dossier)

    champ = champ_source(dossier)
    if champ.nil?
      Rails.logger.info "ExcelVersGrist: champ #{@params[:champ]} absent du dossier #{dossier.number}"
      return
    end

    fichiers = fichiers_xlsx(champ)
    if fichiers.empty?
      Rails.logger.info "ExcelVersGrist: aucun #{EXTENSION} sur #{@params[:champ]} (dossier #{dossier.number})"
      return
    end

    traiter(demarche, dossier, fichiers)
  rescue StandardError => e
    signaler_erreur(e, demarche, dossier)
  end

  private

  # La donnée peut vivre côté usager (champ) ou côté agent (annotation privée) :
  # on cherche dans les deux sans présumer, la configuration ne désignant qu'un
  # libellé.
  def champ_source(dossier)
    (dossier.champs.to_a + dossier.annotations.to_a).find do |champ|
      champ.label == @params[:champ] && champ.__typename == 'PieceJustificativeChamp'
    end
  end

  def fichiers_xlsx(champ)
    champ.files.to_a.select { |file| File.extname(file.filename.to_s).casecmp(EXTENSION).zero? }
  end

  def signaler_erreur(erreur, demarche, dossier)
    Rails.logger.error "ExcelVersGrist: Erreur dossier #{dossier.number}: #{erreur.message}"
    Rails.logger.error erreur.backtrace.join("\n") if erreur.backtrace
    Sentry.capture_exception(erreur, extra: { dossier: dossier.number, demarche: demarche.id })

    raise erreur unless @params.dig(:options, 'continuer_si_erreur') == true
  end

  def colonne_empreinte
    @params.dig(:options, 'colonne_empreinte') || COLONNE_EMPREINTE_DEFAUT
  end

  # Empreinte du contenu, prise à la source : le checksum MD5 exposé par
  # Mes-Démarches sur chaque fichier. Ni Grist ni Baserow n'exposent d'empreinte
  # de contenu, le signal robuste vient donc de la source.
  #
  # Un PieceJustificative peut porter plusieurs fichiers : les empreintes sont
  # triées avant concaténation, pour être insensibles à l'ordre de remontée
  # GraphQL, et écrites en une seule valeur. Le workflow n8n écrivait une
  # empreinte par fichier, la dernière écrasant les précédentes.
  def empreinte_source(fichiers)
    fichiers.map { |file| file.checksum.to_s }.sort.join(',')
  end

  def a_jour?(empreinte, ligne_principale)
    return false if ligne_principale.nil?

    stockee = ligne_principale.dig('fields', colonne_empreinte)
    stockee.present? && stockee != SENTINELLE_A_TRAITER && stockee == empreinte
  end

  # Colonne technique, toujours créée si absente. `isFormula: false` avec une
  # `formula` non vide définit une valeur par défaut Grist appliquée aux
  # nouvelles lignes.
  def ensure_colonne_empreinte(table)
    return if table.columns.key?(colonne_empreinte)

    table.create_columns([{
                           id: colonne_empreinte,
                           fields: { label: colonne_empreinte, type: 'Text',
                                     isFormula: false, formula: %("#{SENTINELLE_A_TRAITER}") }
                         }])
    Rails.logger.info "ExcelVersGrist: colonne #{colonne_empreinte} créée (défaut #{SENTINELLE_A_TRAITER.inspect})"
  end

  # Correspondance colonne source -> { cible, type }.
  #
  # Sans déclaration, toutes les colonnes du fichier sont reprises sous leur nom
  # sanitizé et leur type inféré. Avec déclaration, seules les colonnes citées
  # sont reprises — c'est le moyen d'ignorer le reste du fichier.
  #
  # Le rattachement se fait par nom d'en-tête, jamais par position : robuste au
  # réordonnancement des colonnes d'un dossier à l'autre.
  def mapping(colonnes)
    declare = @params[:colonnes]
    return colonnes.to_h { |col| [col.nom, { cible: col.nom, type: col.type_infere }] } if declare.blank?

    par_nom = colonnes.index_by(&:nom)
    declare.each_with_object({}) do |(source, cible), acc|
      col = par_nom[source]
      if col.nil?
        erreurs_metier << "Colonne source absente du fichier : #{source}"
        next
      end
      acc[source] = cible_normalisee(cible, col)
    end
  end

  def cible_normalisee(cible, colonne)
    return { cible: cible, type: colonne.type_infere } unless cible.is_a?(Hash)

    type = TYPES_YAML[cible['type'].to_s.downcase] || colonne.type_infere
    { cible: cible['cible'] || colonne.nom, type: type }
  end

  # Crée les colonnes cibles absentes et rapporte les conflits de type.
  #
  # Le type d'une colonne existante n'est jamais modifié (spec §7.1) : le
  # parcours assumé est de traiter un premier fichier, ajuster les types à la
  # main dans Grist, puis retraiter.
  def ensure_colonnes(table, correspondance)
    existantes = table.columns
    signaler_conflits_de_type(existantes, correspondance)

    manquantes = correspondance.each_value.reject { |m| existantes.key?(m[:cible]) }.uniq
    return [] if manquantes.empty? || @params.dig(:options, 'creer_colonnes_manquantes') == false

    table.create_columns(manquantes.map { |m| { id: m[:cible], fields: { label: m[:cible], type: m[:type] } } })
    noms = manquantes.map { |m| m[:cible] }
    Rails.logger.info "ExcelVersGrist: colonne(s) créée(s) : #{noms.join(', ')}"
    noms
  end

  def signaler_conflits_de_type(existantes, correspondance)
    correspondance.each_value do |m|
      meta = existantes[m[:cible]]
      next if meta.nil? || meta[:type] == m[:type]

      message = "Type divergent sur #{m[:cible]} : Grist=#{meta[:type]}, attendu=#{m[:type]} (non modifié)"
      Rails.logger.warn "ExcelVersGrist: #{message}"
      erreurs_metier << message
    end
  end

  def table_lignes
    Grist::Config.table(@params[:grist]['doc_id'], @params[:grist]['table_id'], @params[:grist]['token_config'])
  end

  def table_principale
    nom = @params[:grist]['table_principale'] || 'Dossiers'
    Grist::Config.table(@params[:grist]['doc_id'], nom, @params[:grist]['token_config'])
  end

  def ligne_principale(table, dossier_number)
    type = table.columns.dig('Dossier', :type)
    table.find_by('Dossier', MesDemarchesToGrist::GristRef.encode_key(dossier_number, type)).first
  end

  def traiter(_demarche, dossier, fichiers)
    empreinte = empreinte_source(fichiers)
    principale = table_principale
    ensure_colonne_empreinte(principale)

    ligne = ligne_principale(principale, dossier.number)
    if a_jour?(empreinte, ligne)
      Rails.logger.info "ExcelVersGrist: dossier #{dossier.number} à jour, rien à faire"
      return
    end

    nb_lignes = recopier_lignes(dossier, fichiers)

    if nb_lignes == AUCUNE_LIGNE_EXPLOITABLE
      erreurs_metier << 'Aucune ligne exploitable dans le fichier : ni recopie ni suppression'
      ecrire_erreurs(principale, ligne)
      Rails.logger.warn "ExcelVersGrist: dossier #{dossier.number} laissé à retraiter (aucune ligne exploitable)"
      return
    end

    # L'empreinte n'est écrite qu'ici, en aval d'un upsert intégralement réussi :
    # tout échec laisse le dossier à retraiter au passage suivant. Le workflow
    # n8n l'écrivait sur une branche parallèle, et un upsert en échec y perdait
    # les lignes en silence.
    ecrire_empreinte(principale, ligne, empreinte)
    ecrire_erreurs(principale, ligne)
    Rails.logger.info "ExcelVersGrist: dossier #{dossier.number} — #{nb_lignes} ligne(s) recopiée(s)"
  end

  # Renvoie le nombre de lignes recopiées, ou AUCUNE_LIGNE_EXPLOITABLE.
  #
  # Zéro ligne est ambigu : soit le fichier a légitimement été vidé, soit la
  # configuration est fausse (mauvaise feuille, mauvaise ligne d'en-tête, mapping
  # qui ne correspond à rien). Par défaut on suppose le second cas et on ne
  # touche à rien — sinon une erreur de configuration effacerait les lignes du
  # dossier *et* l'empreinte le marquerait comme traité, donc jamais repris.
  #
  # `autoriser_fichier_vide: true` bascule vers l'autre lecture : zéro ligne fait
  # foi et la table est vidée pour ce dossier.
  def recopier_lignes(dossier, fichiers)
    lignes, colonnes = extraire(fichiers)
    correspondance = mapping(colonnes)
    cible = table_lignes
    ensure_colonnes(cible, correspondance)

    lignes_cibles = projeter(lignes, correspondance)
    return AUCUNE_LIGNE_EXPLOITABLE if lignes_cibles.empty? && !fichier_vide_autorise?

    upserter = MesDemarchesToGrist::LigneUpserter.new(cible, field_metadata: cible.columns)
    upserter.upsert_lignes(dossier.number, lignes_cibles)
    upserter.supprimer_orphelins(dossier.number, lignes_cibles.size)
    lignes_cibles.size
  end

  def fichier_vide_autorise?
    @params.dig(:options, 'autoriser_fichier_vide') == true
  end

  # Seul le dernier fichier .xlsx est exploité, comme dans GetSheets : un champ
  # multi-fichiers correspond en pratique à des versions successives.
  def extraire(fichiers)
    PieceJustificativeCache.get(fichiers.last) do |chemin|
      reader = Excel::SheetReader.new(chemin, feuille: @params[:feuille], ligne_entete: @params[:ligne_entete])
      [reader.lignes, reader.colonnes]
    ensure
      reader&.close
    end
  end

  # Projette les lignes source sur les colonnes cibles, en coerçant chaque
  # valeur vers le type de sa cible. Les lignes entièrement vides sont écartées.
  def projeter(lignes, correspondance)
    projetees = lignes.map do |ligne|
      correspondance.each_with_object({}) do |(source, m), acc|
        acc[m[:cible]] = Excel::SheetReader.coercer(ligne[source], m[:type])
      end
    end

    retenues = projetees.reject { |projetee| projetee.each_value.all?(&:blank?) }
    ignorees = projetees.size - retenues.size
    erreurs_metier << "#{ignorees} ligne(s) ignorée(s) (vides)" if ignorees.positive?
    retenues
  end

  def ecrire_empreinte(table, ligne, empreinte)
    return if ligne.nil?

    table.update_records([{ id: ligne['id'], fields: { colonne_empreinte => empreinte } }])
  end

  def colonne_erreurs
    @params.dig(:options, 'colonne_erreurs')
  end

  # Rend les erreurs de données visibles dans Grist, au niveau du dossier, plutôt
  # que noyées dans les logs et Sentry — utile à l'instructeur comme au débogage
  # d'une configuration sur des Excel legacy.
  #
  # La colonne est créée si besoin, indépendamment de creer_colonnes_manquantes :
  # c'est une colonne technique requise par l'option, pas une colonne de données.
  #
  # Elle est vidée en cas de succès, sinon l'erreur d'un passage précédent
  # resterait affichée alors que le dossier est reparti correct.
  def ecrire_erreurs(table, ligne)
    return if colonne_erreurs.blank? || ligne.nil?

    table.create_columns([{ id: colonne_erreurs, fields: { label: colonne_erreurs, type: 'Text' } }]) unless table.columns.key?(colonne_erreurs)

    table.update_records([{ id: ligne['id'], fields: { colonne_erreurs => erreurs_metier.join(' ; ') } }])
  end
end
