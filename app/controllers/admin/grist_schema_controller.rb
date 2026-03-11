# frozen_string_literal: true

module Admin
  class GristSchemaController < ApplicationController
    before_action :authenticate_user!
    # Security: CSRF protection is disabled for JSON API endpoints only.
    # These endpoints require user authentication (authenticate_user!) and only process JSON data.
    skip_before_action :verify_authenticity_token, only: %i[
      organizations workspaces documents tables preview build
      preview_repetable_blocks build_repetable_blocks
    ]

    def index; end

    def repetable_blocks; end

    # GET /admin/grist_schema/organizations
    def organizations
      return render_authentication_error unless current_user

      client = Grist::Config.client
      orgs = client.list_organizations

      render json: {
        success: true,
        organizations: orgs.map { |org| { id: org['id'], name: org['name'] } }
      }
    rescue Grist::APIError => e
      render json: { success: false, error: "Erreur API Grist: #{e.message}" }, status: 422
    rescue StandardError => e
      render_unexpected_error(e)
    end

    # GET /admin/grist_schema/workspaces?org_id=X
    def workspaces
      org_id = params[:org_id]
      return render_validation_error('org_id requis') if org_id.blank?

      client = Grist::Config.client
      ws_list = client.list_workspaces(org_id)

      render json: {
        success: true,
        workspaces: ws_list.map { |ws| { id: ws['id'], name: ws['name'], docs: format_docs(ws) } }
      }
    rescue Grist::APIError => e
      render json: { success: false, error: "Erreur API Grist: #{e.message}" }, status: 422
    end

    # GET /admin/grist_schema/documents?workspace_id=X
    def documents
      workspace_id = params[:workspace_id]
      return render_validation_error('workspace_id requis') if workspace_id.blank?

      client = Grist::Config.client
      workspace = client.get_workspace(workspace_id)
      docs = workspace['docs'] || []

      render json: {
        success: true,
        documents: docs.map { |doc| { id: doc['id'], name: doc['name'] } }
      }
    rescue Grist::APIError => e
      render json: { success: false, error: "Erreur API Grist: #{e.message}" }, status: 422
    end

    # GET /admin/grist_schema/tables?doc_id=X
    def tables
      doc_id = params[:doc_id]
      return render_validation_error('doc_id requis') if doc_id.blank?

      client = Grist::Config.client
      result = client.list_tables(doc_id)
      tables_list = result['tables'] || []

      render json: {
        success: true,
        tables: tables_list.map { |t| { id: t['id'], name: t['id'] } }
      }
    rescue Grist::APIError => e
      render json: { success: false, error: "Erreur API Grist: #{e.message}" }, status: 422
    end

    # POST /admin/grist_schema/preview
    def preview
      demarche_number = params[:demarche_number]&.to_i
      doc_id = params[:doc_id]
      table_id = params[:table_id]
      schema_options = extract_schema_options

      return render_validation_error('demarche_number, doc_id et table_id requis') if demarche_number.blank? || doc_id.blank? || table_id.blank?

      schema_builder = MesDemarchesToGrist::SchemaBuilder.new(demarche_number, doc_id, table_id, schema_options)
      preview_data = schema_builder.preview

      render json: { success: true, preview: preview_data }
    rescue MesDemarchesToGrist::SchemaBuilder::SchemaError => e
      render json: { success: false, error: e.message }, status: 422
    rescue StandardError => e
      render json: { success: false, error: "Erreur inattendue: #{e.message}" }, status: 500
    end

    # POST /admin/grist_schema/build
    def build
      demarche_number = params[:demarche_number]&.to_i
      doc_id = params[:doc_id]
      table_id = params[:table_id]
      selected_fields = params[:selected_fields] || []
      schema_options = extract_schema_options

      return render_validation_error('demarche_number, doc_id et table_id requis') if demarche_number.blank? || doc_id.blank? || table_id.blank?

      schema_builder = MesDemarchesToGrist::SchemaBuilder.new(demarche_number, doc_id, table_id, schema_options)
      report = schema_builder.build!(selected_fields: selected_fields)

      render json: { success: true, report: report }
    rescue MesDemarchesToGrist::SchemaBuilder::SchemaError => e
      render json: { success: false, error: e.message }, status: 422
    rescue StandardError => e
      render json: { success: false, error: "Erreur inattendue: #{e.message}" }, status: 500
    end

    # POST /admin/grist_schema/preview_repetable_blocks
    def preview_repetable_blocks
      params_hash = extract_repetable_params
      return render_validation_error(params_hash[:error]) if params_hash[:error]

      builder = MesDemarchesToGrist::RepetableBlockBuilder.new(
        params_hash[:demarche_number],
        params_hash[:doc_id],
        params_hash[:main_table_id]
      )

      preview_data = builder.preview

      render json: { success: true, preview: preview_data }
    rescue MesDemarchesToGrist::RepetableBlockBuilder::BlockError => e
      render json: { success: false, error: e.message }, status: 422
    rescue StandardError => e
      render json: { success: false, error: "Erreur inattendue: #{e.message}" }, status: 500
    end

    # POST /admin/grist_schema/build_repetable_blocks
    def build_repetable_blocks
      params_hash = extract_repetable_params
      return render_validation_error(params_hash[:error]) if params_hash[:error]

      builder = MesDemarchesToGrist::RepetableBlockBuilder.new(
        params_hash[:demarche_number],
        params_hash[:doc_id],
        params_hash[:main_table_id]
      )

      report = builder.build!(params[:blocks] || [])

      render json: { success: true, report: report }
    rescue MesDemarchesToGrist::RepetableBlockBuilder::BlockError => e
      render json: { success: false, error: e.message }, status: 422
    rescue StandardError => e
      render json: { success: false, error: "Erreur inattendue: #{e.message}" }, status: 500
    end

    private

    def extract_schema_options
      {
        include_fields: ActiveModel::Type::Boolean.new.cast(params[:include_fields]),
        include_annotations: ActiveModel::Type::Boolean.new.cast(params[:include_annotations]),
        include_identity_info: ActiveModel::Type::Boolean.new.cast(params[:include_identity_info]),
        collision_strategy: params[:collision_strategy] || 'skip',
        field_prefix: params[:field_prefix].presence,
        annotation_prefix: params[:annotation_prefix].presence,
        demandeur_type: params[:demandeur_type] || 'mixte'
      }
    end

    def extract_repetable_params
      demarche_number = params[:demarche_number]&.to_i
      doc_id = params[:doc_id]
      main_table_id = params[:main_table_id]

      return { error: 'demarche_number, doc_id et main_table_id requis' } if demarche_number.blank? || doc_id.blank? || main_table_id.blank?

      {
        demarche_number: demarche_number,
        doc_id: doc_id,
        main_table_id: main_table_id
      }
    end

    def format_docs(workspace)
      (workspace['docs'] || []).map { |doc| { id: doc['id'], name: doc['name'] } }
    end

    def render_authentication_error
      render json: { success: false, error: 'Utilisateur non connecté' }, status: 401
    end

    def render_validation_error(message)
      render json: { success: false, error: message }, status: 400
    end

    def render_unexpected_error(error)
      Rails.logger.error "GristSchema error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      render json: { success: false, error: "Erreur inattendue: #{error.message}" }, status: 500
    end
  end
end
