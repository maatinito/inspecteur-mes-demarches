# frozen_string_literal: true

module SchemaBuilders
  # Builder agnostique pour les tables liées aux blocs répétables d'une démarche.
  #
  # Pour chaque `RepetitionChampDescriptor` (dans champ_descriptors OU
  # annotation_descriptors), une table est créée portant le nom du bloc.
  # Chaque table de bloc reçoit en plus des champs métier :
  #   - Ligne (number/Integer) : index de l'occurrence
  #   - Dossier (link_row/Ref vers la table principale, single relationship)
  #   - Bloc (primary, formula : "Dossier-Ligne") — note: la conversion du
  #     champ primaire en formula est laissée à la cible/sync downstream
  #     car certaines API la rejettent à la création.
  #
  # Le format des field-specs est délégué au `TypeMapper#field_spec` ;
  # les champs structurels (Ligne, Dossier, Bloc) sont construits ici car ils
  # n'ont pas d'équivalent côté Mes-Démarches.
  class BlockBuilder
    attr_reader :target, :type_mapper, :field_filter

    def initialize(target:, type_mapper:, field_filter: nil)
      @target = target
      @type_mapper = type_mapper
      @field_filter = field_filter
    end

    # Retourne le plan : une entrée par bloc répétable.
    # `main_table_id` requis car les champs Dossier (link_row/Ref) en dépendent.
    # `application_id` n'est pas utilisé ici mais conservé pour la symétrie avec
    # build! et faciliter d'éventuelles évolutions (filtrage par app, etc.).
    def preview(demarche_descriptor, application_id:, main_table_id:) # rubocop:disable Lint/UnusedMethodArgument
      blocks_from(demarche_descriptor).map do |block|
        {
          block_descriptor_id: block_id_for(block),
          table_name: block.label,
          fields: fields_for(block, main_table_id)
        }
      end
    end

    # Pour chaque bloc, crée la table si absente sinon synchronise ses champs.
    # Retourne un tableau de specs avec `table_id` et `action: :created|:updated`.
    def build!(demarche_descriptor, application_id:, main_table_id:)
      preview(demarche_descriptor, application_id: application_id, main_table_id: main_table_id).map do |spec|
        if target.table_exists?(application_id, spec[:table_name])
          existing = find_existing_table(application_id, spec[:table_name])
          table_id = existing && (existing['id'] || existing[:id])
          target.update_fields(table_id, spec[:fields])
          spec.merge(table_id: table_id, action: :updated)
        else
          created = target.create_table(application_id, spec[:table_name], spec[:fields])
          table_id = created.is_a?(Hash) ? (created['id'] || created[:id]) : nil
          spec.merge(table_id: table_id, action: :created)
        end
      end
    end

    private

    # Extrait tous les RepetitionChampDescriptor (champs ET annotations).
    def blocks_from(demarche_descriptor)
      all = []
      all.concat(Array(demarche_descriptor.champ_descriptors)) if demarche_descriptor.respond_to?(:champ_descriptors) && demarche_descriptor.champ_descriptors
      all.concat(Array(demarche_descriptor.annotation_descriptors)) if demarche_descriptor.respond_to?(:annotation_descriptors) && demarche_descriptor.annotation_descriptors
      all.select { |d| d.__typename == 'RepetitionChampDescriptor' }
    end

    def block_id_for(block)
      block.respond_to?(:id) ? block.id : nil
    end

    # Construit les champs d'une table de bloc : structurels + métier.
    def fields_for(block, main_table_id)
      structural_fields(main_table_id) + business_fields(block)
    end

    # Champs métier (les champ_descriptors du bloc).
    def business_fields(block)
      inner = block.respond_to?(:champ_descriptors) ? Array(block.champ_descriptors) : []
      inner.filter_map { |c| spec_for_descriptor(c) }
    end

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

    # Champs structurels (Ligne + Dossier) — au format natif selon la cible.
    # Bloc (formula primary) n'est PAS créé ici : sa conversion est faite
    # par la cible downstream (cf. MesDemarchesToBaserow::RepetableBlockBuilder
    # qui patche le champ primaire après création).
    def structural_fields(main_table_id)
      case type_mapper.target
      when :baserow then baserow_structural_fields(main_table_id)
      when :grist   then grist_structural_fields(main_table_id)
      else []
      end
    end

    def baserow_structural_fields(main_table_id)
      [
        { type: 'number', name: 'Ligne', number_decimal_places: 0 },
        {
          type: 'link_row',
          name: 'Dossier',
          link_row_table_id: main_table_id,
          has_related_field: true,
          link_row_multiple_relationships: false
        }
      ]
    end

    def grist_structural_fields(main_table_id)
      [
        { id: 'Ligne', fields: { label: 'Ligne', type: 'Integer', isFormula: false } },
        { id: 'Dossier', fields: { label: 'Dossier', type: "Ref:#{main_table_id}", isFormula: false } },
        { id: 'Bloc', fields: {
          label: 'Bloc', type: 'Text', isFormula: true,
          formula: "str($Dossier.Dossier) + '-' + str($Ligne)"
        } }
      ]
    end

    def find_existing_table(application_id, table_name)
      tables = Array(target.list_tables(application_id))
      tables.find do |t|
        name = t['name'] || t[:name] || t['id'] || t[:id]
        name.to_s.casecmp(table_name.to_s).zero?
      end
    end

    def stringify_keys(hash)
      return hash unless hash.is_a?(Hash)

      hash.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
    end
  end
end
