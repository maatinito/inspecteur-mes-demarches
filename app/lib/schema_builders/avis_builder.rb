# frozen_string_literal: true

module SchemaBuilders
  # Builder agnostique pour la table "Avis" associée à une démarche.
  #
  # Le schéma est FIXE (pas dérivé de la démarche). Il reproduit la structure
  # créée par `MesDemarchesToBaserow::AvisTableBuilder` :
  #   - Avis (primary, text)
  #   - Dossier (link_row vers la table principale, single relationship)
  #   - Question, Réponse (long_text)
  #   - Libellé question (text)
  #   - Réponse fermée (boolean)
  #   - Date question, Date réponse (date)
  #   - Email expert, Email demandeur (email)
  #   - Pièces jointes (file)
  #
  # Pour Grist : mêmes libellés (la synchro apparie par libellé), colonne
  # Avis (id de l'avis, clé d'upsert), Dossier en Ref vers la table principale
  # affichant le numéro de dossier, dates avec heure (délai de réponse).
  class AvisBuilder
    class BuilderError < StandardError; end

    TABLE_NAME = 'Avis'

    # Champs standards (hors Dossier qui est un link_row, géré séparément).
    # Format Baserow natif.
    STANDARD_FIELDS = [
      { name: 'Question', type: 'long_text' },
      { name: 'Réponse', type: 'long_text' },
      { name: 'Libellé question', type: 'text' },
      { name: 'Réponse fermée', type: 'boolean' },
      { name: 'Date question', type: 'date' },
      { name: 'Date réponse', type: 'date' },
      { name: 'Email expert', type: 'email' },
      { name: 'Email demandeur', type: 'email' },
      { name: 'Pièces jointes', type: 'file' }
    ].freeze

    # Champs standards au format Grist natif : [libellé, type Grist].
    GRIST_STANDARD_FIELDS = [
      ['Question', 'Text'],
      ['Réponse', 'Text'],
      ['Libellé question', 'Text'],
      ['Réponse fermée', 'Bool'],
      ['Date question', 'DateTime:UTC'],
      ['Date réponse', 'DateTime:UTC'],
      ['Email expert', 'Text'],
      ['Email demandeur', 'Text'],
      ['Pièces jointes', 'Attachments']
    ].freeze

    attr_reader :target, :type_mapper

    def initialize(target:, type_mapper: nil)
      @target = target
      @type_mapper = type_mapper
    end

    # Retourne le plan : nom de la table + liste de champs natifs.
    # `application_id` : identifiant de l'application Baserow (database).
    # `main_table_id` : table principale à laquelle le champ "Dossier"
    # de la table Avis doit pointer (link_row).
    # `demarche_number` : nomme la table Grist Avis_<n°> (un document Grist peut
    # réunir plusieurs démarches) ; sans effet pour Baserow (une base par démarche).
    def preview(application_id:, main_table_id:, demarche_number: nil)
      {
        table_name: table_name(demarche_number),
        application_id: application_id,
        main_table_id: main_table_id,
        fields: fields_for_preview(main_table_id)
      }
    end

    # Crée la table si absente, sinon ajoute les champs manquants
    # (ne touche pas aux colonnes existantes — alignement sur le comportement
    # de l'original AvisTableBuilder).
    def build!(application_id:, main_table_id:, demarche_number: nil)
      name = table_name(demarche_number)
      result = if target.table_exists?(application_id, name)
                 existing = find_existing_table(application_id, name)
                 table_id = existing && (existing['id'] || existing[:id])
                 target.update_fields(target.table_ref(application_id, table_id), all_fields_for_build(main_table_id))
                 { table_id: table_id, table_name: name, action: :updated }
               else
                 created = target.create_table(application_id, name, all_fields_for_build(main_table_id))
                 table_id = created.is_a?(Hash) ? (created['id'] || created[:id]) : nil
                 { table_id: table_id, table_name: name, action: :created }
               end
      target.show_dossier_number(application_id, result[:table_id], main_table_id) if result[:table_id]
      result
    end

    # Nom de la table Avis : Avis_<n° démarche> côté Grist, Avis côté Baserow.
    def table_name(demarche_number = nil)
      grist? && demarche_number ? "#{TABLE_NAME}_#{demarche_number}" : TABLE_NAME
    end

    private

    def grist?
      type_mapper&.target == :grist
    end

    # Spec du champ "Dossier" (link_row vers la table principale).
    def dossier_link_field(main_table_id)
      {
        type: 'link_row',
        name: 'Dossier',
        link_row_table_id: main_table_id,
        has_related_field: true,
        link_row_multiple_relationships: false
      }
    end

    # Champs au format natif de la cible (utilisés pour la preview ET le build).
    def fields_for_preview(main_table_id)
      return grist_fields(main_table_id) if grist?

      [dossier_link_field(main_table_id)] + STANDARD_FIELDS.map(&:dup)
    end

    # Ids forcés pour Avis (clé d'upsert) et Dossier (référencé par la formule
    # d'affichage, comme dans les tables de blocs) ; les autres sont assainis.
    def grist_fields(main_table_id)
      [
        { id: 'Avis', fields: { label: 'Avis', type: 'Text', isFormula: false } },
        { id: 'Dossier', fields: { label: 'Dossier', type: "Ref:#{main_table_id}", isFormula: false } }
      ] + GRIST_STANDARD_FIELDS.map { |label, type| type_mapper.literal_field_spec(label, type) }
    end

    def all_fields_for_build(main_table_id)
      fields_for_preview(main_table_id)
    end

    def find_existing_table(application_id, table_name)
      tables = Array(target.list_tables(application_id))
      tables.find do |t|
        name = t['name'] || t[:name] || t['id'] || t[:id]
        Target.same_table_name?(name, table_name)
      end
    end
  end
end
