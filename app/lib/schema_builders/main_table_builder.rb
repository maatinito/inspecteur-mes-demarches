# frozen_string_literal: true

module SchemaBuilders
  # Builder agnostique de la cible pour la table principale d'une démarche.
  #
  # Itère sur les `champ_descriptors` (et optionnellement `annotation_descriptors`)
  # d'un `demarche_descriptor` GraphQL ; ignore les types ignorés (sections /
  # explications) et non supportés (cf. TypeMapper) ; construit le spec natif
  # à la cible via `TypeMapper#field_spec` ; puis appelle `Target#create_table`
  # ou `Target#update_fields` selon que la table existe déjà ou non.
  #
  # Le format des field-specs est délégué au `TypeMapper` qui sait produire
  # la forme native attendue par la cible (Baserow flat hash vs Grist
  # `{id:, fields:}`).
  class MainTableBuilder
    # Colonne primaire portant le numéro de dossier Mes-Démarches.
    DOSSIER_FIELD_NAME = SchemaBuilders::MetadataFields.dossier.name

    attr_reader :target, :type_mapper, :field_filter

    def initialize(target:, type_mapper:, field_filter: nil)
      @target = target
      @type_mapper = type_mapper
      @field_filter = field_filter
    end

    # Retourne le plan de construction sans rien créer côté cible.
    # `demarche_descriptor` est une démarche GraphQL (objet répondant à
    # `champ_descriptors`/`annotation_descriptors` ou contenant une révision).
    # `excluded_field_ids`: IDs MD (champ_descriptor.id) à filtrer avant
    # transformation en field-spec natif.
    # `demandeur_modes`: modes demandeur détectés (Array de :physique/:morale) ;
    # détermine les colonnes d'identité ajoutées (cf. MetadataFields).
    def preview(demarche_descriptor, application_id:, table_name:, include_annotations: true,
                excluded_field_ids: [], demandeur_modes: [])
      fields = build_field_specs(demarche_descriptor, include_annotations: include_annotations,
                                                      excluded_field_ids: excluded_field_ids,
                                                      demandeur_modes: demandeur_modes)
      {
        table_name: table_name,
        application_id: application_id,
        fields: fields
      }
    end

    # Crée la table si absente, sinon synchronise ses champs.
    # `existing_table_id` : id (nu) d'une table déjà sélectionnée/synchronisée
    # (combo « Table principale »). S'il est fourni et que la table existe
    # toujours côté cible, on la met à jour au lieu d'en recréer une — évite la
    # recréation à chaque synchro quand la table a été renommée.
    # `demandeur_modes` : cf. #preview.
    # Retourne `{ table_id:, table_name:, action: :created | :updated, fields: [...] }`.
    def build!(demarche_descriptor, application_id:, table_name:, include_annotations: true,
               excluded_field_ids: [], existing_table_id: nil, demandeur_modes: [])
      fields = build_field_specs(demarche_descriptor, include_annotations: include_annotations,
                                                      excluded_field_ids: excluded_field_ids,
                                                      demandeur_modes: demandeur_modes)

      table_id = resolve_existing_table_id(application_id, table_name, existing_table_id)

      if table_id
        target.update_fields(target.table_ref(application_id, table_id), fields)
        { table_id: table_id, table_name: table_name, action: :updated, fields: fields }
      else
        created = target.create_table(application_id, table_name, fields)
        { table_id: extract_table_id(created), table_name: table_name, action: :created, fields: fields }
      end
    end

    private

    # Détermine l'id de la table à mettre à jour, ou nil s'il faut la créer.
    # 1. Table explicitement sélectionnée (combo) et toujours présente côté cible.
    # 2. Repli : correspondance par nom (compat comportement historique).
    def resolve_existing_table_id(application_id, table_name, existing_table_id)
      return existing_table_id if existing_table_id.present? && table_id_present?(application_id, existing_table_id)
      return nil unless target.table_exists?(application_id, table_name)

      existing = find_existing_table(application_id, table_name)
      existing && (existing['id'] || existing[:id])
    end

    def table_id_present?(application_id, table_id)
      Array(target.list_tables(application_id)).any? do |t|
        (t['id'] || t[:id]).to_s == table_id.to_s
      end
    end

    def extract_table_id(created)
      return nil unless created.is_a?(Hash)

      created['id'] || created[:id]
    end

    # Récupère la révision (draft ou published) et concatène champs + annotations.
    def collect_descriptors(demarche_descriptor, include_annotations:)
      descriptors = []
      descriptors.concat(Array(demarche_descriptor.champ_descriptors)) if demarche_descriptor.respond_to?(:champ_descriptors) && demarche_descriptor.champ_descriptors
      if include_annotations && demarche_descriptor.respond_to?(:annotation_descriptors) && demarche_descriptor.annotation_descriptors
        descriptors.concat(Array(demarche_descriptor.annotation_descriptors))
      end
      descriptors
    end

    def build_field_specs(demarche_descriptor, include_annotations:, excluded_field_ids: [], demandeur_modes: [])
      excluded_set = Array(excluded_field_ids).to_set(&:to_s)
      descriptor_specs = collect_descriptors(demarche_descriptor, include_annotations: include_annotations).filter_map do |descriptor|
        spec_for_descriptor(descriptor, excluded_set: excluded_set)
      end
      dedupe_specs(metadata_field_specs(demandeur_modes, excluded_set) + descriptor_specs)
    end

    # Déduplique les specs par identifiant de colonne cible (id Grist / name
    # Baserow), en gardant la PREMIÈRE occurrence. Indispensable car un champ ou
    # une annotation de la démarche peut porter le même libellé qu'une colonne de
    # métadonnée (ex. « Raison sociale » présent comme annotation ET comme champ
    # demandeur) : sans ça, deux colonnes de même id sont envoyées à la cible,
    # ce qui casse la création/MAJ (Grist refuse, ou crée des doublons).
    # Les métadonnées étant en tête, elles l'emportent (schéma déterministe).
    def dedupe_specs(specs)
      seen = Set.new
      specs.select do |spec|
        key = spec[:id] || spec[:name]
        key.nil? || seen.add?(key)
      end
    end

    # Colonnes de métadonnées (Dossier + système + identité demandeur) au format
    # natif de la cible, depuis la source unique MetadataFields.
    # Les colonnes système exclues dans le diff (metadata:<clé>) sont omises.
    def metadata_field_specs(demandeur_modes, excluded_set = Set.new)
      MetadataFields.retenues(demandeur_modes, excluded_set).map { |field| metadata_spec(field) }
    end

    # Construit le field spec natif d'un MetadataFields::Field.
    #
    # Côté Grist, on force l'id de la colonne Dossier à 'Dossier' (et non l'id
    # assaini en minuscules) car les formules des tables de blocs y référencent
    # explicitement `$Dossier.Dossier`. Les autres colonnes gardent leur id
    # assaini (la synchro apparie par libellé).
    def metadata_spec(field)
      options = field.options ? { 'options' => field.options } : {}
      spec = type_mapper.field_spec(field.name, field.typename, options)
      spec[:id] = field.name if field.primary? && spec.key?(:id)
      spec
    end

    # Construit un field spec natif pour un descripteur Mes-Démarches.
    # Renvoie nil si le type est ignoré, non supporté, exclu explicitement,
    # ou rejeté par le filtre.
    def spec_for_descriptor(descriptor, excluded_set: Set.new)
      field_type = descriptor.__typename
      return nil if TypeMapper.should_ignore_type?(field_type)
      return nil unless type_mapper.supported_type?(field_type)
      return nil if descriptor.respond_to?(:id) && excluded_set.include?(descriptor.id.to_s)
      return nil if field_filter && !filter_accepts?(descriptor)

      field_name = type_mapper.generate_field_name(descriptor.label)
      descriptor_hash = descriptor.respond_to?(:to_h) ? descriptor.to_h : {}
      type_mapper.field_spec(field_name, field_type, stringify_keys(descriptor_hash))
    rescue TypeMapper::UnsupportedTypeError
      nil
    end

    def filter_accepts?(descriptor)
      if field_filter.respond_to?(:call)
        field_filter.call(descriptor)
      elsif field_filter.respond_to?(:accepts?)
        field_filter.accepts?(descriptor)
      else
        true
      end
    end

    def find_existing_table(application_id, table_name)
      tables = Array(target.list_tables(application_id))
      tables.find do |t|
        name = t['name'] || t[:name] || t['id'] || t[:id]
        name.to_s.casecmp(table_name.to_s).zero?
      end
    end

    # Convertit les clés symbols en strings (les TypeMapper attendent des
    # clés string dans le descriptor — cf. spec existant).
    def stringify_keys(hash)
      return hash unless hash.is_a?(Hash)

      hash.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
    end
  end
end
