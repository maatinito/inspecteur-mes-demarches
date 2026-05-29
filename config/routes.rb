# frozen_string_literal: true

Rails.application.routes.draw do
  root 'demarche#show'
  devise_for :users

  get 'demarche/verify'
  get 'demarche/report'
  put 'demarche/post_message/:dossier', to: 'demarche#post_message', as: :demarche_post_message

  get 'configurations', to: 'demarche#show', as: 'configuration'

  # Admin routes
  namespace :admin do
    resources :baserow_schema, only: [:index] do
      collection do
        get :workspaces
        get :applications
        get :tables
        get :test_auth
        post :preview
        post :build

        # Routes pour blocs répétables
        get :repetable_blocks
        post :preview_repetable_blocks
        post :build_repetable_blocks

        # Routes pour la table Avis
        post :preview_avis_table
        post :build_avis_table
      end
    end

    resources :grist_schema, only: [:index] do
      collection do
        get :organizations
        get :workspaces
        get :documents
        get :tables
        post :preview
        post :build

        # Routes pour blocs répétables
        get :repetable_blocks
        post :preview_repetable_blocks
        post :build_repetable_blocks
      end
    end

    # Refonte UI : SchemaBuilder scopé par démarche
    resources :demarches, only: [], param: :demarche_id do
      resource :schema, only: [:show], controller: 'schema_builder' do
        post   'targets',                          to: 'schema_builder#create_target',           as: :create_target
        delete 'targets/:target_type',             to: 'schema_builder#destroy_target',          as: :destroy_target
        patch  'targets/:target_type/selection',   to: 'schema_builder#update_target_selection', as: :update_target_selection
        get    'targets/:target_type/workspaces',                  to: 'schema_builder#list_workspaces',   as: :list_workspaces
        get    'targets/:target_type/applications/:workspace_id',  to: 'schema_builder#list_applications', as: :list_applications
        get    'targets/:target_type/tables/:application_id',      to: 'schema_builder#list_tables',       as: :list_tables
      end
    end
  end

  # view jobs
  match '/delayed_job' => DelayedJobWeb, :anchor => false, :via => %i[get post]

  #
  # Letter Opener
  #

  mount LetterOpenerWeb::Engine, at: '/letter_opener' if Rails.env.development?
end
