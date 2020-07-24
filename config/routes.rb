# frozen_string_literal: true

Rails.application.routes.draw do
  root 'check#report'

  get 'check/verify'
  get 'check/report'
  put 'check/post_message/:dossier', to: 'check#post_message', as: :check_post_message

  # view jobs
  match '/delayed_job' => DelayedJobWeb, :anchor => false, :via => %i[get post]
end
