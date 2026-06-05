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
  # Pour Grist : non supporté pour l'instant — raise NotImplementedError.
  # (Les link_row Baserow et les Ref Grist ont des sémantiques différentes
  # qui doivent être conçues dans une slice ultérieure.)
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

    attr_reader :target, :type_mapper

    def initialize(target:, type_mapper: nil)
      @target = target
      @type_mapper = type_mapper
      check_supported!
    end

    # Retourne le plan : nom de la table + liste de champs natifs.
    # `application_id` : identifiant de l'application Baserow (database).
    # `main_table_id` : table principale à laquelle le champ "Dossier"
    # de la table Avis doit pointer (link_row).
    def preview(application_id:, main_table_id:)
      check_supported!
      {
        table_name: TABLE_NAME,
        application_id: application_id,
        main_table_id: main_table_id,
        fields: fields_for_preview(main_table_id)
      }
    end

    # Crée la table si absente, sinon ajoute les champs manquants
    # (ne touche pas aux colonnes existantes — alignement sur le comportement
    # de l'original AvisTableBuilder).
    def build!(application_id:, main_table_id:)
      check_supported!

      if target.table_exists?(application_id, TABLE_NAME)
        existing = find_existing_table(application_id, TABLE_NAME)
        table_id = existing && (existing['id'] || existing[:id])
        target.update_fields(table_id, all_fields_for_build(main_table_id))
        { table_id: table_id, table_name: TABLE_NAME, action: :updated }
      else
        created = target.create_table(application_id, TABLE_NAME, all_fields_for_build(main_table_id))
        table_id = created.is_a?(Hash) ? (created['id'] || created[:id]) : nil
        { table_id: table_id, table_name: TABLE_NAME, action: :created }
      end
    end

    private

    def check_supported!
      raise NotImplementedError, 'Avis non supporté par Grist pour l\'instant' if target.is_a?(SchemaBuilders::GristTarget)
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

    # Champs au format natif Baserow (utilisés pour la preview ET le build).
    def fields_for_preview(main_table_id)
      [dossier_link_field(main_table_id)] + STANDARD_FIELDS.map(&:dup)
    end

    def all_fields_for_build(main_table_id)
      fields_for_preview(main_table_id)
    end

    def find_existing_table(application_id, table_name)
      tables = Array(target.list_tables(application_id))
      tables.find do |t|
        name = t['name'] || t[:name] || t['id'] || t[:id]
        name.to_s.casecmp(table_name.to_s).zero?
      end
    end
  end
end
