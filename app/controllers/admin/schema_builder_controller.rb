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

    private

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
  end
end
