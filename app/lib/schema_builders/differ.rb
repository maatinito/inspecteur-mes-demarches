# frozen_string_literal: true

module SchemaBuilders
  # Compare les champs d'un demarche_descriptor Mes-Démarches avec ceux présents
  # côté cible (Baserow / Grist), pour la table principale et pour les blocs
  # répétables. Retourne 4 collections par section : to_add / to_modify / ok / excluded.
  #
  # API :
  #   differ = SchemaBuilders::Differ.new(
  #     target: schema_target,
  #     adapter: SchemaBuilders::BaserowTarget.new,
  #     demarche_descriptor: descriptor
  #   )
  #   differ.main_table_diff
  #   differ.blocks_diff
  #
  # Voir docs/superpowers/specs/2026-05-29-builder-diff-exclusion-design.md.
  class Differ
    REPETITION_TYPENAME = 'RepetitionChampDescriptor'

    def initialize(target:, adapter:, demarche_descriptor:)
      @target = target
      @adapter = adapter
      @demarche_descriptor = demarche_descriptor
    end

    def main_table_diff
      md_fields = filterable_main_fields
      target_fields = fetch_target_fields(@target.main_table_external_id)

      classify(md_fields, target_fields,
               excluded_predicate: ->(f) { @target.field_excluded?(f[:id]) })
    end

    # Calcule le diff par bloc répétable :
    #   - Les blocs entiers exclus sont retournés à part (id + label seuls).
    #   - Pour les autres, on auto-crée le SchemaBlockTarget si absent et on
    #     calcule un diff interne identique à celui de la table principale.
    #
    # Retourne :
    # {
    #   blocks_excluded: [{ id:, label: }, ...],
    #   blocks: [
    #     { id:, label:, excluded: false, schema_block_target:, diff: {...} },
    #     ...
    #   ]
    # }
    def blocks_diff
      blocks = Array(@demarche_descriptor.champ_descriptors)
               .select { |c| c.__typename == REPETITION_TYPENAME }
      excluded, included = blocks.partition { |b| @target.block_excluded?(b.id) }

      {
        blocks_excluded: excluded.map { |b| { id: b.id, label: b.label } },
        blocks: included.map { |b| block_entry(b) }
      }
    end

    private

    # Entrée diff pour un bloc inclus : auto-création du SchemaBlockTarget,
    # puis classification de ses champs internes.
    def block_entry(block)
      block_target = ensure_block_target(block)
      inner_md_fields = Array(block.champ_descriptors).map { |c| descriptor_to_field(c) }
      inner_target_fields = fetch_target_fields(block_target.backend_table_id)

      inner_diff = classify(inner_md_fields, inner_target_fields,
                            excluded_predicate: ->(f) { block_target.field_excluded?(f[:id]) })

      {
        id: block.id,
        label: block.label,
        excluded: false,
        schema_block_target: block_target,
        diff: inner_diff
      }
    end

    # Auto-crée le SchemaBlockTarget s'il n'existe pas encore.
    # backend_table_id reste nil jusqu'au premier Build du bloc — c'est juste
    # un porteur d'état pour stocker les exclusions de champs.
    def ensure_block_target(block)
      @target.schema_block_targets.find_or_create_by!(block_descriptor_id: block.id)
    end

    # Champs candidats pour la table principale (hors blocs répétables).
    def filterable_main_fields
      Array(@demarche_descriptor.champ_descriptors)
        .reject { |c| c.__typename == REPETITION_TYPENAME }
        .map { |c| descriptor_to_field(c) }
    end

    # Récupère la liste des champs côté cible pour une table donnée.
    # Retourne [] si pas de table externe (premier build) ou en cas d'erreur.
    def fetch_target_fields(external_table_id)
      return [] if external_table_id.blank?

      Array(@adapter.get_table_fields(external_table_id)).map do |f|
        {
          name: f['name'] || f[:name],
          type: f['type'] || f[:type]
        }
      end
    rescue StandardError => e
      Rails.logger.warn "SchemaBuilders::Differ: unable to fetch target fields for #{external_table_id}: #{e.message}"
      []
    end

    # Classe chaque champ MD dans l'une des 4 collections.
    def classify(md_fields, target_fields, excluded_predicate:)
      result = { to_add: [], to_modify: [], ok: [], excluded: [] }
      target_by_name = target_fields.index_by { |f| f[:name] }

      md_fields.each do |field|
        if excluded_predicate.call(field)
          result[:excluded] << field
        elsif (existing = target_by_name[field[:label]])
          if compatible?(field, existing)
            result[:ok] << field
          else
            result[:to_modify] << field.merge(divergence: divergence_label(field, existing))
          end
        else
          result[:to_add] << field
        end
      end

      result
    end

    # Transforme un champ_descriptor MD en hash normalisé.
    def descriptor_to_field(champ)
      {
        id: champ.id,
        label: champ.label,
        type: simple_type_for(champ),
        options: (champ.respond_to?(:options) ? champ.options : nil)
      }
    end

    # 'TextChampDescriptor' -> 'text', 'IntegerNumberChampDescriptor' -> 'integer_number'
    def simple_type_for(champ)
      type = champ.__typename.to_s.sub('ChampDescriptor', '')
      type.gsub(/(.)([A-Z])/, '\1_\2').downcase
    end

    # Heuristique de compatibilité v1, volontairement laxiste :
    # on flag uniquement si l'un est numérique et l'autre non.
    def compatible?(md_field, target_field)
      numeric?(md_field[:type]) == numeric?(target_field[:type])
    end

    def numeric?(type)
      type.to_s.match?(/integer|decimal|number|float/)
    end

    def divergence_label(md_field, target_field)
      "Type cible '#{target_field[:type]}' ne correspond pas à '#{md_field[:type]}'"
    end
  end
end
