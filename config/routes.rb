# frozen_string_literal: true

Rails.application.routes.draw do
  root "check#report"
  devise_for :users

  get 'check/verify'
  get 'check/report'
  put 'check/post_message/:dossier', to: 'check#post_message', as: :check_post_message

  # view jobs
  match '/delayed_job' => DelayedJobWeb, :anchor => false, :via => %i[get post]

  #
  # Letter Opener
  #

  mount LetterOpenerWeb::Engine, at: '/letter_opener' if Rails.env.development?
end
