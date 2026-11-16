# frozen_string_literal: true

module Admin
  class SchemaBuilderController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!
    before_action :set_demarche

    def show
      @schema_targets = @demarche.schema_targets.order(:target_type)
      # Auto-détection (best-effort) de la table Avis existante côté Baserow.
      # Permet d'afficher le badge "Sync OK" plutôt que "Jamais sync" pour les
      # démarches déjà synchronisées via l'ancien builder. Idempotent : skip
      # si avis_table_external_id déjà connu.
      @schema_targets.each { |t| autodetect_avis_table(t) }
    end

    def create_target
      target = @demarche.schema_targets.new(target_type: params[:target_type])
      if target.save
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              'schema-targets',
              partial: 'target_tabs',
              locals: { demarche: @demarche, targets: @demarche.schema_targets.order(:target_type) }
            )
          end
          format.html { redirect_to admin_demarche_schema_path(demarche_demarche_id: @demarche.id) }
        end
      else
        head :unprocessable_entity
      end
    end

    def destroy_target
      target = @demarche.schema_targets.find_by!(target_type: params[:target_type])
      target.destroy!
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            'schema-targets',
            partial: 'target_tabs',
            locals: { demarche: @demarche, targets: @demarche.schema_targets.order(:target_type) }
          )
        end
        format.html { redirect_to admin_demarche_schema_path(demarche_demarche_id: @demarche.id) }
      end
    end

    def update_target_selection
      target = @demarche.schema_targets.find_by!(target_type: params[:target_type])
      return head :unprocessable_entity unless target.update(target_selection_params)

      head :ok
    end

    def list_workspaces
      render json: target_adapter.list_workspaces
    end

    def list_applications
      render json: target_adapter.list_applications(params[:workspace_id])
    end

    def list_tables
      render json: target_adapter.list_tables(params[:application_id])
    end

    def preview_main_table
      target = @demarche.schema_targets.find_by!(target_type: params[:target])
      diff = differ_for(target).main_table_diff

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "main-table-#{target.id}",
            partial: 'main_table_section',
            locals: { target: target, diff: diff }
          )
        end
        format.html do
          render partial: 'main_table_section', locals: { target: target, diff: diff }
        end
      end
    end

    def build_main_table
      target = @demarche.schema_targets.find_by!(target_type: params[:target])
      builder = main_table_builder_for(target)
      table_name = main_table_name_for(target)
      table_id = builder.resolve_table_id(application_id: target.application_external_id, table_name: table_name,
                                          existing_table_id: target.main_table_external_id.presence)
      erreur = refus_avant_ecriture(target, table_id)
      return render_build_error('main-table', 'main_table_section', target, { error: erreur }) if erreur

      result = builder.build!(
        demarche_descriptor,
        application_id: target.application_external_id,
        table_name: table_name,
        existing_table_id: table_id,
        excluded_field_ids: target.exclusions_effectives,
        demandeur_modes: demandeur_modes
      )
      target.update!(main_table_external_id: result[:table_id].to_s, last_synced_at: Time.current)
      result = finaliser_dlnuf(result) if target.dlnuf?

      render turbo_stream: turbo_stream.replace(
        "main-table-#{target.id}",
        partial: 'main_table_section',
        locals: { target: target, build_result: result }
      )
    end

    def retablir_marqueur
      target = @demarche.schema_targets.find_by!(target_type: params[:target])
      result = begin
        referentiel_dlnuf.retablir!(target.main_table_external_id)
        { info: 'Marqueur rétabli.' }
      rescue Referentiel::Verrou::Refus => e
        { error: e.message }
      end
      render_build_error('main-table', 'main_table_section', target, result)
    end

    # Vide la table DLNUF (blocs puis principale) et remet au début le curseur de toutes les
    # démarches de ce robot qui l'alimentent. L'autorisation vient du marqueur lu sur la table ;
    # un type figé autrement par ce robot (archive, inconnu) refuse. Sans enregistrement local
    # (builder sur un robot qui ne synchronise pas), seul le marqueur décide.
    def vider_table
      target = @demarche.schema_targets.find_by!(target_type: params[:target])
      table_id = target.main_table_external_id
      return head :forbidden if !target.baserow? || table_id.blank?
      return head :forbidden if ReferentielTable.where(backend: 'baserow', table_ref: table_id.to_s).where.not(mode: 'dlnuf').exists?

      begin
        return head :forbidden unless referentiel_dlnuf.type_lu(table_id) == :dlnuf

        result = { info: vider_tables(target, table_id) }
      rescue Baserow::APIError => e
        result = { error: "Effacement interrompu : #{e.message}. Le curseur de la démarche n'a pas été modifié." }
      end
      render_build_error('main-table', 'main_table_section', target, result)
    end

    def preview_avis
      target = @demarche.schema_targets.find_by!(target_type: params[:target])
      return head :precondition_failed if target.main_table_external_id.blank? || target.dlnuf?

      diff = compute_avis_diff(target)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "avis-#{target.id}",
            partial: 'avis_section',
            locals: { target: target, diff: diff }
          )
        end
        format.html do
          render partial: 'avis_section', locals: { target: target, diff: diff }
        end
      end
    end

    def build_avis
      target = @demarche.schema_targets.find_by!(target_type: params[:target])
      return head :precondition_failed if target.main_table_external_id.blank? || target.dlnuf?

      builder = avis_builder_for(target)
      result = builder.build!(application_id: target.application_external_id, main_table_id: target.main_table_external_id,
                              demarche_number: @demarche.id)
      # TODO: last_synced_at est partagé entre main_table et avis ; envisager un avis_last_synced_at dédié.
      target.update!(avis_table_external_id: result[:table_id].to_s, last_synced_at: Time.current)

      render turbo_stream: turbo_stream.replace(
        "avis-#{target.id}",
        partial: 'avis_section',
        locals: { target: target, build_result: result }
      )
    end

    def preview_blocks
      target = @demarche.schema_targets.find_by!(target_type: params[:target])
      return head :precondition_failed if target.main_table_external_id.blank?

      diff = differ_for(target).blocks_diff

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "blocks-#{target.id}",
            partial: 'blocks_section',
            locals: { target: target, diff: diff }
          )
        end
        format.html do
          render partial: 'blocks_section', locals: { target: target, diff: diff }
        end
      end
    end

    def build_blocks
      target = @demarche.schema_targets.find_by!(target_type: params[:target])
      return head :precondition_failed if target.main_table_external_id.blank?

      erreur = refus_avant_ecriture(target, target.main_table_external_id)
      return render_build_error('blocks', 'blocks_section', target, [], erreur: erreur) if erreur

      builder = block_builder_for(target)
      erreur = refus_tables_de_bloc(target, builder)
      return render_build_error('blocks', 'blocks_section', target, [], erreur: erreur) if erreur

      excluded_fields_per_block = exclusions_par_bloc(target)
      results = builder.build!(
        demarche_descriptor,
        application_id: target.application_external_id,
        main_table_id: target.main_table_external_id,
        excluded_block_ids: target.excluded_block_descriptor_ids,
        excluded_fields_per_block: excluded_fields_per_block
      )

      results.each do |r|
        block = target.schema_block_targets.find_or_initialize_by(block_descriptor_id: r[:block_descriptor_id])
        block.update!(backend_table_id: r[:table_id].to_s, last_synced_at: Time.current)
      end

      render turbo_stream: turbo_stream.replace(
        "blocks-#{target.id}",
        partial: 'blocks_section',
        locals: { target: target.reload, build_result: results }
      )
    end

    def toggle_main_table_field_exclusion
      target = @demarche.schema_targets.find_by!(target_type: params[:target])
      excluded = ActiveModel::Type::Boolean.new.cast(params[:excluded])
      return head :unprocessable_entity if excluded && target.dlnuf? && params[:field_id] == SchemaTarget::EMAIL_USAGER_ID

      if excluded
        target.exclude_field!(params[:field_id])
      else
        target.include_field!(params[:field_id])
      end

      diff = differ_for(target).main_table_diff

      render turbo_stream: turbo_stream.replace(
        "main-table-#{target.id}",
        partial: 'main_table_section',
        locals: { target: target, diff: diff }
      )
    end

    def toggle_block_exclusion
      target = @demarche.schema_targets.find_by!(target_type: params[:target])
      excluded = ActiveModel::Type::Boolean.new.cast(params[:excluded])
      if excluded
        target.exclude_block!(params[:block_id])
      else
        target.include_block!(params[:block_id])
      end

      diff = differ_for(target).blocks_diff
      render turbo_stream: turbo_stream.replace(
        "blocks-#{target.id}",
        partial: 'blocks_section',
        locals: { target: target, diff: diff }
      )
    end

    def toggle_block_field_exclusion
      target = @demarche.schema_targets.find_by!(target_type: params[:target])
      block_target = target.schema_block_targets.find_by!(block_descriptor_id: params[:block_id])
      excluded = ActiveModel::Type::Boolean.new.cast(params[:excluded])
      if excluded
        block_target.exclude_field!(params[:field_id])
      else
        block_target.include_field!(params[:field_id])
      end

      diff = differ_for(target).blocks_diff
      render turbo_stream: turbo_stream.replace(
        "blocks-#{target.id}",
        partial: 'blocks_section',
        locals: { target: target, diff: diff }
      )
    end

    private

    def referentiel_dlnuf
      @referentiel_dlnuf ||= SchemaBuilders::ReferentielDlnuf.new(client: Baserow::StructureClient.new)
    end

    # Avant toute écriture sur une table principale existante (Baserow) : le type lu sur la
    # table doit être celui de la cible, et une table DLNUF ne porte aucune colonne fichier.
    # Rend le message d'erreur, ou nil.
    def refus_avant_ecriture(target, table_id)
      return unless target.baserow? && table_id.present?

      lu = referentiel_dlnuf.type_lu(table_id)
      return 'Marqueur illisible sur la table.' if lu == :invalid
      return 'Le type d\'une table ne change pas : créer une nouvelle table.' unless lu.to_s == target.referentiel
      return unless target.dlnuf?

      fichiers = referentiel_dlnuf.colonnes_fichier(table_id)
      "Colonne(s) fichier interdite(s) dans une table DLNUF : #{fichiers.join(', ')}." if fichiers.any?
    rescue Baserow::APIError => e
      "Lecture de la table #{table_id} impossible : #{e.message}"
    end

    def exclusions_par_bloc(target)
      target.schema_block_targets.to_h { |bt| [bt.block_descriptor_id, bt.excluded_field_ids] }
    end

    # DLNUF : build! réutilise une table de même nom ; elle doit être liée à CETTE table principale
    # et sans colonne fichier, sinon rien n'est écrit. Rend le message d'erreur, ou nil.
    def refus_tables_de_bloc(target, builder)
      return unless target.dlnuf?

      application = target.application_external_id
      principale = target.main_table_external_id
      liees = referentiel_dlnuf.tables_liees(application, principale)
      blocs = builder.preview(demarche_descriptor, application_id: application, main_table_id: principale,
                                                   excluded_block_ids: target.excluded_block_descriptor_ids)
      blocs.each do |bloc|
        existante = builder.existing_table_id(application, bloc[:table_name])
        next unless existante

        unless liees.include?(existante.to_i)
          return "La table de bloc #{bloc[:table_name]} n'appartient pas à cette table DLNUF : " \
                 'la renommer ou choisir une autre application.'
        end

        fichiers = referentiel_dlnuf.colonnes_fichier(existante)
        return "Colonne(s) fichier interdite(s) dans une table DLNUF : #{fichiers.join(', ')}." if fichiers.any?
      end
      nil
    rescue Baserow::APIError => e
      "Lecture des tables de bloc impossible : #{e.message}"
    end

    # Efface les tables de blocs puis la principale ; les curseurs ne sont remis qu'une fois tout
    # effacé. Les démarches qui alimentent la table sont lues AVANT d'effacer : une configuration
    # illisible n'efface rien.
    def vider_tables(target, table_id)
      adapter = target_adapter_for(target)
      alimentent = ConfigurationsBaserow.demarches_synchronisees_vers(table_id) | [@demarche.id]
      # Tables de bloc lues sur Baserow (colonne Dossier liée à la principale), jamais les
      # backend_table_id enregistrés : détectés par nom, ils peuvent désigner une autre table.
      blocs = referentiel_dlnuf.tables_liees(referentiel_dlnuf.application_de(table_id), table_id)
      tables = blocs + [table_id]
      effacees = tables.sum { |id| adapter.vider_table(id) }
      numeros = Demarche.where(id: alimentent).order(:id).pluck(:id)
      Demarche.where(id: numeros).update_all(checked_at: DossierActions::EPOCH, updated_at: Time.zone.now)
      "#{effacees} ligne(s) effacée(s). Curseur remis au début pour la ou les démarche(s) #{numeros.join(', ')} : " \
        'elles seront retraitées depuis le début au prochain passage du robot.'
    end

    # Pose ou vérifie le marqueur DLNUF après la construction de la table principale.
    def finaliser_dlnuf(result)
      referentiel_dlnuf.finaliser!(result[:table_id], creee: result[:action] == :created)
      result
    rescue Referentiel::Verrou::Refus => e
      result.merge(error: e.message)
    rescue Baserow::APIError => e
      result.merge(error: erreur_marqueur_dlnuf(result, e))
    end

    def erreur_marqueur_dlnuf(result, erreur)
      table = "« #{result[:table_name]} » (ID #{result[:table_id]})"
      if result[:action] == :created
        "Table #{table} créée, mais son marqueur DLNUF n'a pas pu être écrit (#{erreur.message}) : " \
          'supprimer la table dans Baserow avant de construire de nouveau.'
      else
        "Lecture du marqueur DLNUF de la table #{table} impossible : #{erreur.message}"
      end
    end

    def render_build_error(prefix, partial, target, build_result, **extra)
      render turbo_stream: turbo_stream.replace(
        "#{prefix}-#{target.id}",
        partial: partial,
        locals: { target: target, build_result: build_result, **extra }
      )
    end

    def differ_for(target)
      SchemaBuilders::Differ.new(
        target: target,
        adapter: target_adapter_for(target),
        type_mapper: target.type_mapper,
        demarche_descriptor: demarche_descriptor,
        demandeur_modes: demandeur_modes
      )
    end

    def set_demarche
      # L'accès au controller est déjà restreint aux admins via require_admin!.
      # Les admins doivent voir toutes les démarches (sysadmin = opérateur
      # technique, pas instructeur métier), donc pas de scoping demarches_users.
      @demarche = Demarche.find(params[:demarche_demarche_id])
    end

    def target_selection_params
      params.permit(:workspace_external_id, :application_external_id, :main_table_external_id, :referentiel)
    end

    def target_adapter
      case params[:target_type]
      when 'baserow' then SchemaBuilders::BaserowTarget.new
      when 'grist'   then SchemaBuilders::GristTarget.new
      else raise ActionController::ParameterMissing, 'unknown target_type'
      end
    end

    def main_table_builder_for(target)
      adapter = target_adapter_for(target)
      type_mapper = target.type_mapper
      field_filter = build_field_filter(target)

      SchemaBuilders::MainTableBuilder.new(target: adapter, type_mapper: type_mapper, field_filter: field_filter)
    end

    def avis_builder_for(target)
      adapter = target_adapter_for(target)
      type_mapper = target.type_mapper
      SchemaBuilders::AvisBuilder.new(target: adapter, type_mapper: type_mapper)
    end

    def block_builder_for(target)
      adapter = target_adapter_for(target)
      type_mapper = target.type_mapper
      field_filter = build_field_filter(target)
      SchemaBuilders::BlockBuilder.new(target: adapter, type_mapper: type_mapper, field_filter: field_filter)
    end

    def target_adapter_for(target)
      case target.target_type
      when 'baserow' then SchemaBuilders::BaserowTarget.new
      when 'grist'   then SchemaBuilders::GristTarget.new
      end
    end

    # FieldFilter exclut les champs read-only existants côté cible.
    # Nécessite la table cible : avant build initial (main_table_external_id absent),
    # on retourne nil (pas de filtre) — le builder traitera tous les champs supportés.
    def build_field_filter(target)
      return nil if target.main_table_external_id.blank?

      case target.target_type
      when 'baserow'
        SchemaBuilders::FieldFilter.for(:baserow, table_id: target.main_table_external_id, token_config: nil)
      when 'grist'
        SchemaBuilders::FieldFilter.for(:grist, doc_id: target.application_external_id, table_id: target.main_table_external_id, config_name: nil)
      end
    end

    # Objet démarche GraphQL (mémoïsé pour la requête). Expose la révision et un
    # échantillon de dossiers (pour la détection du type de demandeur).
    def demarche_object
      @demarche_object ||= begin
        result = MesDemarches.query(MesDemarches::Queries::DemarcheRevision, variables: { demarche: @demarche.id })
        raise "Erreur accès démarche #{@demarche.id}: #{result.errors.messages.values.flatten.join(', ')}" if result.errors.any?

        demarche = result.data&.demarche
        raise "Démarche #{@demarche.id} introuvable ou accès non autorisé" if demarche.nil?

        demarche
      end
    end

    # Charge le descripteur GraphQL de la démarche et retourne sa révision (draft
    # ou published) qui expose `champ_descriptors` / `annotation_descriptors`
    # consommés par MainTableBuilder.
    def demarche_descriptor
      revision = demarche_object.draft_revision || demarche_object.published_revision
      raise "Démarche #{@demarche.id} sans révision disponible" unless revision

      revision
    end

    # Détecte le(s) mode(s) demandeur de la démarche en échantillonnant un
    # dossier (le type est figé par la démarche, jamais mixte). Repli sur les
    # deux modes si aucun dossier n'existe encore (indétectable).
    def demandeur_modes
      @demandeur_modes ||= begin
        nodes = demarche_object.dossiers&.nodes || []
        typename = nodes.first&.demandeur&.__typename
        mode = SchemaBuilders::MetadataFields.mode_for_typename(typename)
        mode ? [mode] : %i[physique morale]
      rescue StandardError => e
        Rails.logger.warn "demandeur_modes: détection impossible (#{e.message}), repli sur les deux modes"
        %i[physique morale]
      end
    end

    def main_table_name_for(_target)
      "Dossiers démarche #{@demarche.id}"
    end

    # Calcule un diff léger entre les 6 champs Avis attendus et la table Avis
    # côté Baserow (si elle existe). 3 zones : to_add / to_modify / ok.
    # Pas de notion d'exclusion (schéma fixe).
    def compute_avis_diff(target)
      builder = avis_builder_for(target)
      expected_fields = builder.preview(
        application_id: target.application_external_id,
        main_table_id: target.main_table_external_id,
        demarche_number: @demarche.id
      )[:fields]
      actual_fields = fetch_avis_target_fields(target)
      classify_avis_fields(expected_fields, actual_fields)
    end

    def fetch_avis_target_fields(target)
      return [] if target.avis_table_external_id.blank?

      adapter = target_adapter_for(target)
      ref = adapter.table_ref(target.application_external_id, target.avis_table_external_id)
      Array(adapter.get_table_fields(ref)).map do |f|
        { name: f['name'] || f[:name], type: f['type'] || f[:type] }
      end
    rescue StandardError => e
      Rails.logger.warn "fetch_avis_target_fields: #{e.message}"
      []
    end

    def classify_avis_fields(expected, actual)
      result = { to_add: [], to_modify: [], ok: [] }
      actual_by_name = actual.index_by { |f| f[:name].to_s }

      expected.each do |field|
        # Baserow : { name:, type: } ; Grist : { id:, fields: { label:, type: } }.
        name = (field[:name] || field.dig(:fields, :label)).to_s
        type = (field[:type] || field.dig(:fields, :type)).to_s
        existing = actual_by_name[name]
        normalized = { name: name, type: type }

        if existing.nil?
          result[:to_add] << normalized
        elsif existing[:type].to_s == type
          result[:ok] << normalized
        else
          result[:to_modify] << normalized.merge(divergence: "Type cible '#{existing[:type]}' ne correspond pas à '#{type}'")
        end
      end

      result
    end

    # Best-effort : si la table Avis existe déjà côté cible (cas typique des
    # démarches synchronisées par l'ancien builder), on persiste son ID pour
    # éviter le faux "Jamais sync" dans le dashboard (Grist : la table n'a pas
    # de nom, seulement un id). Erreurs silencieuses pour ne pas casser le show.
    def autodetect_avis_table(target)
      return if target.avis_table_external_id.present?
      return if target.application_external_id.blank?

      adapter = target_adapter_for(target)
      tables = Array(adapter.list_tables(target.application_external_id))
      match = tables.find do |t|
        SchemaBuilders::Target.same_table_name?(t['name'] || t[:name] || t['id'] || t[:id], avis_builder_for(target).table_name(@demarche.id))
      end
      target.update!(avis_table_external_id: (match['id'] || match[:id]).to_s) if match
    rescue StandardError => e
      Rails.logger.warn "autodetect_avis_table: #{e.message} (target #{target.id})"
    end
  end
end
