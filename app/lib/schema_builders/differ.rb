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

    def initialize(target:, adapter:, demarche_descriptor:, type_mapper: nil)
      @target = target
      @adapter = adapter
      @demarche_descriptor = demarche_descriptor
      @type_mapper = type_mapper || TypeMapper.for(target.target_type.to_sym)
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
      blocks = all_descriptors.select { |c| c.__typename == REPETITION_TYPENAME }
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
      inner_md_fields = Array(block.champ_descriptors)
                        .reject { |c| ignored_descriptor?(c) }
                        .map { |c| descriptor_to_field(c) }
      inner_md_fields = dedupe_by_label(inner_md_fields, context: "bloc '#{block.label}'")
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

    # Auto-crée le SchemaBlockTarget s'il n'existe pas encore. Si backend_table_id
    # est absent, on tente de détecter une table existante côté cible par nom
    # (convention historique : table_name = block.label, cf. l'ancien
    # MesDemarchesToBaserow::RepetableBlockBuilder). Si détectée, on persiste
    # le backend_table_id — l'utilisateur n'a pas besoin de rejouer le backfill.
    def ensure_block_target(block)
      block_target = @target.schema_block_targets.find_or_create_by!(block_descriptor_id: block.id)
      if block_target.backend_table_id.blank? && @target.application_external_id.present?
        detected_id = detect_existing_block_table_id(block.label)
        block_target.update!(backend_table_id: detected_id.to_s) if detected_id
      end
      block_target
    end

    # Recherche une table dans l'application cible par nom. Cache la liste pour
    # éviter N+1 appels API quand il y a plusieurs blocs.
    def detect_existing_block_table_id(name)
      tables_by_name[name]
    end

    def tables_by_name
      @tables_by_name ||= begin
        list = Array(@adapter.list_tables(@target.application_external_id))
        list.to_h { |t| [t['name'] || t[:name], t['id'] || t[:id]] }
      rescue StandardError => e
        Rails.logger.warn "SchemaBuilders::Differ: unable to list tables for detection: #{e.message}"
        {}
      end
    end

    # Champs candidats pour la table principale (hors blocs répétables,
    # hors types ignorés / non supportés via TypeMapper, dédupés par label).
    # Inclut champ_descriptors ET annotation_descriptors — cohérent avec
    # MainTableBuilder#build! (include_annotations: true par défaut).
    def filterable_main_fields
      fields = all_descriptors
               .reject { |c| c.__typename == REPETITION_TYPENAME }
               .reject { |c| ignored_descriptor?(c) }
               .map { |c| descriptor_to_field(c) }
      dedupe_by_label(fields, context: 'table principale')
    end

    # Concatène champs utilisateur + annotations privées du descripteur.
    # Les deux collections sont peuplées symétriquement par MainTableBuilder
    # et BlockBuilder à la sync — le Differ doit donc voir la même union
    # pour ne pas afficher de faux "à ajouter".
    def all_descriptors
      list = []
      list.concat(Array(@demarche_descriptor.champ_descriptors)) if @demarche_descriptor.respond_to?(:champ_descriptors)
      list.concat(Array(@demarche_descriptor.annotation_descriptors)) if @demarche_descriptor.respond_to?(:annotation_descriptors)
      list
    end

    # Conserve la première occurrence de chaque label et logue les doublons.
    # Défensif : la plupart des doublons sont déjà filtrés par ignored_descriptor?
    # (un label "Superficie" porté à la fois par un HeaderSection et un
    # IntegerNumber disparaît après le filtre). Ce dédup attrape les cas
    # résiduels (deux champs métier de même label) pour éviter qu'un même
    # nom soit envoyé deux fois à la cible.
    def dedupe_by_label(fields, context:)
      fields.group_by { |f| f[:label] }.flat_map do |label, group|
        if group.size > 1
          Rails.logger.warn(
            "SchemaBuilders::Differ: doublon de label '#{label}' dans #{context}, " \
            "on garde le premier (ids: #{group.map { |f| f[:id] }.inspect})"
          )
        end
        [group.first]
      end
    end

    # Vrai si le descripteur doit être totalement ignoré du diff (sections
    # d'en-tête, explications, types non mappables).
    def ignored_descriptor?(champ)
      typename = champ.__typename.to_s
      TypeMapper.should_ignore_type?(typename) || !@type_mapper.supported_type?(typename)
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
    # `:typename` (interne) garde le __typename d'origine pour permettre au
    # diff de calculer le type cible attendu via TypeMapper.
    def descriptor_to_field(champ)
      {
        id: champ.id,
        label: champ.label,
        typename: champ.__typename.to_s,
        type: expected_target_type(champ),
        options: (champ.respond_to?(:options) ? champ.options : nil)
      }
    end

    # Type natif cible attendu pour ce descripteur (via TypeMapper).
    # Passe le descripteur sérialisé en hash pour que le TypeMapper applique
    # ses règles contextuelles (notamment : DropDownListChampDescriptor avec
    # otherOption=true devient `text` au lieu de `single_select` car la valeur
    # libre saisie par l'usager ne tient pas dans une enum).
    # Retourne nil si le mapping n'est pas trouvable.
    def expected_target_type(champ)
      @type_mapper.map_field_type(champ.__typename.to_s, descriptor_attrs(champ))[:type]
    rescue TypeMapper::UnsupportedTypeError
      nil
    end

    # Sérialise les attributs du descripteur GraphQL utiles au TypeMapper
    # (string keys camelCase, alignés avec ce qu'attend map_field_type).
    # On privilégie #to_h (utilisé par l'ancien MesDemarchesToBaserow::SchemaBuilder)
    # car le graphql-client gem expose les champs en camelCase via to_h, alors
    # que les accesseurs Ruby peuvent varier selon la version. Fallback sur
    # accesseurs si l'objet n'a pas to_h (cas des stubs de test).
    def descriptor_attrs(champ)
      return champ.to_h if champ.respond_to?(:to_h) && !champ.is_a?(Struct)

      {
        'otherOption' => (champ.respond_to?(:other_option) ? champ.other_option : nil),
        'options' => (champ.respond_to?(:options) ? champ.options : nil)
      }
    end

    # Compatibilité de type : on compare le type cible ATTENDU (calculé par
    # le TypeMapper depuis le __typename MD) au type cible RÉEL côté Baserow/Grist.
    # Cas spécial : les formules MD tolèrent N'IMPORTE quel type cible existant
    # (l'utilisateur peut avoir manuellement converti le champ text initial en
    # number, date ou formula Baserow).
    def compatible?(md_field, target_field)
      return true if TypeMapper.formula_type?(md_field[:typename])

      md_field[:type].to_s == target_field[:type].to_s
    end

    def divergence_label(md_field, target_field)
      "Type cible '#{target_field[:type]}' ne correspond pas au type attendu '#{md_field[:type]}'"
    end
  end
end
