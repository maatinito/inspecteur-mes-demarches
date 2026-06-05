# frozen_string_literal: true

Rails.application.routes.draw do
  root 'demarche#show'

  # Inscription publique réactivée : un auto-inscrit a admin: false par défaut.
  # L'accès au schema builder est gated par require_admin! (cf.
  # Admin::SchemaBuilderController). Le scénario phishing (inscrire avec
  # email victim → hériter de ses démarches via update_instructeurs) reste
  # possible côté DemarcheController, mais l'attaquant n'accède qu'à
  # l'interface de vérification, pas au méta-modèle Baserow.
  devise_for :users

  get 'demarche/verify'
  get 'demarche/report'
  put 'demarche/post_message/:dossier', to: 'demarche#post_message', as: :demarche_post_message

  get 'configurations', to: 'demarche#show', as: 'configuration'

  # Admin routes
  namespace :admin do
    # Page de transition pour les anciennes URLs /admin/baserow_schema* et
    # /admin/grist_schema*. Liste les démarches accessibles avec un lien vers
    # le nouveau dashboard scopé par démarche.
    get 'schema_builder_legacy', to: 'schema_builder_legacy#index'

    # Redirections des anciennes pages d'accueil vers la page de transition
    # /admin/schema_builder_legacy (les controllers d'origine ont été supprimés
    # en Phase K — voir docs/REFONTE_UI.md).
    get 'baserow_schema',                  to: redirect('/admin/schema_builder_legacy'), as: :baserow_schema_legacy
    get 'baserow_schema/repetable_blocks', to: redirect('/admin/schema_builder_legacy'), as: :baserow_schema_repetable_blocks_legacy
    get 'grist_schema',                    to: redirect('/admin/schema_builder_legacy'), as: :grist_schema_legacy
    get 'grist_schema/repetable_blocks',   to: redirect('/admin/schema_builder_legacy'), as: :grist_schema_repetable_blocks_legacy

    # Refonte UI : SchemaBuilder scopé par démarche
    resources :demarches, only: [], param: :demarche_id do
      resource :schema, only: [:show], controller: 'schema_builder' do
        post   'targets',                          to: 'schema_builder#create_target',           as: :create_target
        delete 'targets/:target_type',             to: 'schema_builder#destroy_target',          as: :destroy_target
        patch  'targets/:target_type/selection',   to: 'schema_builder#update_target_selection', as: :update_target_selection
        get    'targets/:target_type/workspaces',                  to: 'schema_builder#list_workspaces',   as: :list_workspaces
        get    'targets/:target_type/applications/:workspace_id',  to: 'schema_builder#list_applications', as: :list_applications
        get    'targets/:target_type/tables/:application_id',      to: 'schema_builder#list_tables',       as: :list_tables
        get    'targets/:target/main_table/preview',               to: 'schema_builder#preview_main_table', as: :preview_main_table
        post   'targets/:target/main_table/build',                 to: 'schema_builder#build_main_table',   as: :build_main_table
        get    'targets/:target/avis/preview',                     to: 'schema_builder#preview_avis',       as: :preview_avis
        post   'targets/:target/avis/build',                       to: 'schema_builder#build_avis',         as: :build_avis
        get    'targets/:target/blocks/preview',                   to: 'schema_builder#preview_blocks',     as: :preview_blocks
        post   'targets/:target/blocks/build',                     to: 'schema_builder#build_blocks',       as: :build_blocks
        patch  'targets/:target/main_table/fields/:field_id/exclusion',
               to: 'schema_builder#toggle_main_table_field_exclusion',
               as: :toggle_main_table_field_exclusion
        patch  'targets/:target/blocks/:block_id/exclusion',
               to: 'schema_builder#toggle_block_exclusion',
               as: :toggle_block_exclusion
        patch  'targets/:target/blocks/:block_id/fields/:field_id/exclusion',
               to: 'schema_builder#toggle_block_field_exclusion',
               as: :toggle_block_field_exclusion
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
