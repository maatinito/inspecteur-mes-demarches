# frozen_string_literal: true

module Admin
  class SchemaBuilderController < ApplicationController
    before_action :authenticate_user!
    before_action :set_demarche

    def show
      @schema_targets = @demarche.schema_targets.order(:target_type)
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
      target.update!(target_selection_params)
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
      result = builder.build!(
        demarche_descriptor,
        application_id: target.application_external_id,
        table_name: main_table_name_for(target),
        excluded_field_ids: target.excluded_field_ids
      )
      target.update!(main_table_external_id: result[:table_id].to_s, last_synced_at: Time.current)

      render turbo_stream: turbo_stream.replace(
        "main-table-#{target.id}",
        partial: 'main_table_section',
        locals: { target: target, build_result: result }
      )
    end

    def preview_avis
      target = @demarche.schema_targets.find_by!(target_type: params[:target])
      return head :bad_request if target.target_type == 'grist'
      return head :precondition_failed if target.main_table_external_id.blank?

      builder = avis_builder_for(target)
      result = builder.preview(application_id: target.application_external_id, main_table_id: target.main_table_external_id)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "avis-#{target.id}",
            partial: 'avis_section',
            locals: { target: target, preview: result }
          )
        end
        format.html do
          render partial: 'avis_section', locals: { target: target, preview: result }
        end
      end
    end

    def build_avis
      target = @demarche.schema_targets.find_by!(target_type: params[:target])
      return head :bad_request if target.target_type == 'grist'
      return head :precondition_failed if target.main_table_external_id.blank?

      builder = avis_builder_for(target)
      result = builder.build!(application_id: target.application_external_id, main_table_id: target.main_table_external_id)
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

      builder = block_builder_for(target)
      excluded_fields_per_block = target.schema_block_targets.to_h do |bt|
        [bt.block_descriptor_id, bt.excluded_field_ids]
      end
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

    def differ_for(target)
      SchemaBuilders::Differ.new(
        target: target,
        adapter: target_adapter_for(target),
        demarche_descriptor: demarche_descriptor
      )
    end

    def set_demarche
      @demarche = Demarche.find(params[:demarche_demarche_id])
    end

    def target_selection_params
      params.permit(:workspace_external_id, :application_external_id, :main_table_external_id)
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
      type_mapper = SchemaBuilders::TypeMapper.for(target.target_type.to_sym)
      field_filter = build_field_filter(target)

      SchemaBuilders::MainTableBuilder.new(target: adapter, type_mapper: type_mapper, field_filter: field_filter)
    end

    def avis_builder_for(target)
      adapter = target_adapter_for(target)
      type_mapper = SchemaBuilders::TypeMapper.for(target.target_type.to_sym)
      SchemaBuilders::AvisBuilder.new(target: adapter, type_mapper: type_mapper)
    end

    def block_builder_for(target)
      adapter = target_adapter_for(target)
      type_mapper = SchemaBuilders::TypeMapper.for(target.target_type.to_sym)
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

    # Charge le descripteur GraphQL de la démarche et retourne sa révision (draft
    # ou published) qui expose `champ_descriptors` / `annotation_descriptors`
    # consommés par MainTableBuilder.
    def demarche_descriptor
      result = MesDemarches.query(MesDemarches::Queries::DemarcheRevision, variables: { demarche: @demarche.id })
      raise "Erreur accès démarche #{@demarche.id}: #{result.errors.map(&:message).join(', ')}" if result.errors.any?

      demarche = result.data&.demarche
      raise "Démarche #{@demarche.id} introuvable ou accès non autorisé" if demarche.nil?

      revision = demarche.draft_revision || demarche.published_revision
      raise "Démarche #{@demarche.id} sans révision disponible" unless revision

      revision
    end

    def main_table_name_for(_target)
      "Dossiers démarche #{@demarche.id}"
    end
  end
end
