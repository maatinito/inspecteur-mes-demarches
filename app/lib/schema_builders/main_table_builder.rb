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
    attr_reader :target, :type_mapper, :field_filter

    def initialize(target:, type_mapper:, field_filter: nil)
      @target = target
      @type_mapper = type_mapper
      @field_filter = field_filter
    end

    # Retourne le plan de construction sans rien créer côté cible.
    # `demarche_descriptor` est une démarche GraphQL (objet répondant à
    # `champ_descriptors`/`annotation_descriptors` ou contenant une révision).
    def preview(demarche_descriptor, application_id:, table_name:, include_annotations: true)
      fields = build_field_specs(demarche_descriptor, include_annotations: include_annotations)
      {
        table_name: table_name,
        application_id: application_id,
        fields: fields
      }
    end

    # Crée la table si absente, sinon synchronise ses champs.
    # Retourne `{ table_id:, table_name:, action: :created | :updated, fields: [...] }`.
    def build!(demarche_descriptor, application_id:, table_name:, include_annotations: true)
      fields = build_field_specs(demarche_descriptor, include_annotations: include_annotations)

      if target.table_exists?(application_id, table_name)
        existing = find_existing_table(application_id, table_name)
        table_id = existing && (existing['id'] || existing[:id])
        target.update_fields(table_id, fields)
        { table_id: table_id, table_name: table_name, action: :updated, fields: fields }
      else
        created = target.create_table(application_id, table_name, fields)
        table_id = created.is_a?(Hash) ? (created['id'] || created[:id]) : nil
        { table_id: table_id, table_name: table_name, action: :created, fields: fields }
      end
    end

    private

    # Récupère la révision (draft ou published) et concatène champs + annotations.
    def collect_descriptors(demarche_descriptor, include_annotations:)
      descriptors = []
      descriptors.concat(Array(demarche_descriptor.champ_descriptors)) if demarche_descriptor.respond_to?(:champ_descriptors) && demarche_descriptor.champ_descriptors
      if include_annotations && demarche_descriptor.respond_to?(:annotation_descriptors) && demarche_descriptor.annotation_descriptors
        descriptors.concat(Array(demarche_descriptor.annotation_descriptors))
      end
      descriptors
    end

    def build_field_specs(demarche_descriptor, include_annotations:)
      collect_descriptors(demarche_descriptor, include_annotations: include_annotations).filter_map do |descriptor|
        spec_for_descriptor(descriptor)
      end
    end

    # Construit un field spec natif pour un descripteur Mes-Démarches.
    # Renvoie nil si le type est ignoré, non supporté, ou rejeté par le filtre.
    def spec_for_descriptor(descriptor)
      field_type = descriptor.__typename
      return nil if TypeMapper.should_ignore_type?(field_type)
      return nil unless type_mapper.supported_type?(field_type)
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
