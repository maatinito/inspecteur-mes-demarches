# frozen_string_literal: true

require_relative 'excel/sheet_reader'
require_relative 'mes_demarches_to_grist/grist_ref'

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

  def process(demarche, dossier)
    super
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

  # Complété par les tâches suivantes du plan : mapping des colonnes et upsert
  # des lignes.
  def traiter(_demarche, _dossier, _fichiers)
    nil
  end
end
