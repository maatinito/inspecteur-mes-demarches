# frozen_string_literal: true

Rails.application.routes.draw do
  get 'diese/check'
  get 'diese/report'
  put 'diese/post_message/:dossier', to: 'diese#post_message', as: :post_message
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
