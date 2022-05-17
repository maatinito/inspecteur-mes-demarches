# frozen_string_literal: true

Rails.application.routes.draw do
  root 'demarche#show'
  devise_for :users

  get 'demarche/verify'
  get 'demarche/report'
  put 'demarche/post_message/:dossier', to: 'demarche#post_message', as: :demarche_post_message

  get 'configurations', to: 'demarche#show', as: 'configuration'

  # view jobs
  match '/delayed_job' => DelayedJobWeb, :anchor => false, :via => %i[get post]

  #
  # Letter Opener
  #

  mount LetterOpenerWeb::Engine, at: '/letter_opener' if Rails.env.development?
end
