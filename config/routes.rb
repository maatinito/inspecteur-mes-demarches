# frozen_string_literal: true

Rails.application.routes.draw do
  root 'check#report'

  get 'check/verify'
  get 'check/report'
  put 'check/post_message/:dossier', to: 'check#post_message', as: :check_post_message
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html


end
