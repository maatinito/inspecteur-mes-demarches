# frozen_string_literal: true

module Admin
  class BaserowSchemaController < ApplicationController
    before_action :authenticate_user!
    # Security: CSRF protection is disabled for JSON API endpoints only.
    # These endpoints require user authentication (authenticate_user!) and only process JSON data,
    # making CSRF attacks impractical. Authentication is enforced on all actions.
    skip_before_action :verify_authenticity_token, only: %i[
      workspaces applications tables preview build
      preview_repetable_blocks build_repetable_blocks
    ]

    def index; end

    def repetable_blocks; end

    def test_auth
      render json: {
        success: true,
        user_id: current_user&.id,
        authenticated: current_user.present?
      }
    end

    def workspaces
      Rails.logger.info "Workspaces called by user: #{current_user&.id || 'none'}"
      return render_authentication_error unless current_user

      fetch_and_render_workspaces
    rescue Baserow::AuthService::AuthError => e
      render_baserow_auth_error(e)
    rescue Baserow::ApiError => e
      render_baserow_api_error(e)
    rescue StandardError => e
      render_unexpected_error(e)
    end

    # rubocop:disable Metrics/MethodLength
    def applications
      workspace_id = params[:workspace_id]

      if workspace_id.blank?
        render json: { success: false, error: 'workspace_id requis' }, status: 400
        return
      end

      begin
        structure_client = Baserow::StructureClient.new
        all_applications = structure_client.list_applications(workspace_id)

        # Filtrer les applications par workspace
        workspace_applications = all_applications.select do |app|
          app['workspace'] && app['workspace']['id'].to_s == workspace_id.to_s
        end

        # Ne garder que les bases de données
        database_applications = workspace_applications.select { |app| app['type'] == 'database' }

        render json: {
          success: true,
          applications: database_applications.map do |app|
            {
              id: app['id'],
              name: app['name'],
              type: app['type']
            }
          end
        }
      rescue Baserow::ApiError => e
        render json: {
          success: false,
          error: "Erreur API Baserow: #{e.message}"
        }, status: 422
      end
    end
    # rubocop:enable Metrics/MethodLength

    # rubocop:disable Metrics/MethodLength
    def tables
      application_id = params[:application_id]

      if application_id.blank?
        render json: { success: false, error: 'application_id requis' }, status: 400
        return
      end

      begin
        # Find the application and extract its tables
        structure_client = Baserow::StructureClient.new
        workspace_id = params[:workspace_id] # We need to pass this or get it from session

        unless workspace_id
          render json: { success: false, error: 'workspace_id requis' }, status: 400
          return
        end

        applications = structure_client.list_applications(workspace_id)
        application = applications.find { |app| app['id'].to_s == application_id.to_s }

        unless application
          render json: { success: false, error: 'Application non trouvée' }, status: 404
          return
        end

        tables = application['tables'] || []

        render json: {
          success: true,
          tables: tables.map do |table|
            {
              id: table['id'],
              name: table['name']
            }
          end
        }
      rescue Baserow::APIError => e
        render json: {
          success: false,
          error: "Erreur API Baserow: #{e.message}"
        }, status: 422
      end
    end
    # rubocop:enable Metrics/MethodLength

    def preview
      demarche_number = params[:demarche_number]&.to_i
      table_id = params[:table_id]&.to_i
      schema_options = extract_schema_options

      if demarche_number.blank? || table_id.blank?
        render json: { success: false, error: 'demarche_number et table_id requis' }, status: 400
        return
      end

      begin
        schema_builder = MesDemarchesToBaserow::SchemaBuilder.new(demarche_number, table_id, schema_options)
        preview_data = schema_builder.preview

        render json: {
          success: true,
          preview: preview_data
        }
      rescue MesDemarchesToBaserow::SchemaBuilder::SchemaError => e
        render json: {
          success: false,
          error: e.message
        }, status: 422
      rescue StandardError => e
        render json: {
          success: false,
          error: "Erreur inattendue: #{e.message}"
        }, status: 500
      end
    end

    def build
      demarche_number = params[:demarche_number]&.to_i
      table_id = params[:table_id]&.to_i
      selected_fields = params[:selected_fields] || []
      schema_options = extract_schema_options

      return render_validation_error('demarche_number et table_id requis') if demarche_number.blank? || table_id.blank?

      build_schema(demarche_number, table_id, selected_fields, schema_options)
    end

    def preview_repetable_blocks
      params_hash = extract_repetable_params
      return render_validation_error(params_hash[:error]) if params_hash[:error]

      preview_repetable_blocks_with_params(params_hash)
    end

    def build_repetable_blocks
      params_hash = extract_repetable_params
      return render_validation_error(params_hash[:error]) if params_hash[:error]

      build_repetable_blocks_with_params(params_hash, params[:blocks] || [])
    end

    private

    def extract_schema_options
      log_raw_params
      build_schema_options.tap { |options| Rails.logger.info "Converted options: #{options.inspect}" }
    end

    def log_raw_params
      fields_param = params[:include_fields].inspect
      annotations_param = params[:include_annotations].inspect
      identity_param = params[:include_identity_info].inspect

      Rails.logger.info "Raw params: include_fields=#{fields_param}, " \
                        "include_annotations=#{annotations_param}, " \
                        "include_identity_info=#{identity_param}"
    end

    def build_schema_options
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

    def render_authentication_error
      render json: {
        success: false,
        error: 'Utilisateur non connecté'
      }, status: 401
    end

    def fetch_and_render_workspaces
      structure_client = Baserow::StructureClient.new
      workspaces = structure_client.list_workspaces

      render json: {
        success: true,
        workspaces: workspaces.map { |workspace| format_workspace(workspace) }
      }
    end

    def format_workspace(workspace)
      {
        id: workspace['id'],
        name: workspace['name']
      }
    end

    def render_baserow_auth_error(error)
      render json: {
        success: false,
        error: "Erreur d'authentification Baserow: #{error.message}"
      }, status: 401
    end

    def render_baserow_api_error(error)
      render json: {
        success: false,
        error: "Erreur API Baserow: #{error.message}"
      }, status: 422
    end

    def render_unexpected_error(error)
      Rails.logger.error "Workspaces error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      render json: {
        success: false,
        error: "Erreur inattendue: #{error.message}"
      }, status: 500
    end

    def render_validation_error(message)
      render json: { success: false, error: message }, status: 400
    end

    def build_schema(demarche_number, table_id, selected_fields, schema_options)
      schema_builder = MesDemarchesToBaserow::SchemaBuilder.new(demarche_number, table_id, schema_options)
      report = schema_builder.build!(selected_fields: selected_fields)

      render json: {
        success: true,
        report: report
      }
    rescue MesDemarchesToBaserow::SchemaBuilder::SchemaError => e
      render json: {
        success: false,
        error: e.message
      }, status: 422
    rescue StandardError => e
      render json: {
        success: false,
        error: "Erreur inattendue: #{e.message}"
      }, status: 500
    end

    def extract_repetable_params
      demarche_number = params[:demarche_number]&.to_i
      main_table_id = params[:main_table_id]&.to_i
      application_id = params[:application_id]&.to_i
      workspace_id = params[:workspace_id]&.to_i

      return { error: 'demarche_number, main_table_id, application_id et workspace_id requis' } if demarche_number.blank? || main_table_id.blank? || application_id.blank? || workspace_id.blank?

      {
        demarche_number: demarche_number,
        main_table_id: main_table_id,
        application_id: application_id,
        workspace_id: workspace_id
      }
    end

    def preview_repetable_blocks_with_params(params_hash)
      builder = MesDemarchesToBaserow::RepetableBlockBuilder.new(
        params_hash[:demarche_number],
        params_hash[:main_table_id],
        params_hash[:application_id],
        params_hash[:workspace_id]
      )

      preview_data = builder.preview

      render json: {
        success: true,
        preview: preview_data
      }
    rescue MesDemarchesToBaserow::RepetableBlockBuilder::BlockError => e
      render json: { success: false, error: e.message }, status: 422
    rescue StandardError => e
      render json: { success: false, error: "Erreur inattendue: #{e.message}" }, status: 500
    end

    def build_repetable_blocks_with_params(params_hash, blocks_config)
      builder = MesDemarchesToBaserow::RepetableBlockBuilder.new(
        params_hash[:demarche_number],
        params_hash[:main_table_id],
        params_hash[:application_id],
        params_hash[:workspace_id]
      )

      report = builder.build!(blocks_config)

      render json: {
        success: true,
        report: report
      }
    rescue MesDemarchesToBaserow::RepetableBlockBuilder::BlockError => e
      render json: { success: false, error: e.message }, status: 422
    rescue StandardError => e
      render json: { success: false, error: "Erreur inattendue: #{e.message}" }, status: 500
    end
  end
end
