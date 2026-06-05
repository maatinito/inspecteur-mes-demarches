# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Legacy schema URLs', type: :request do
  let(:user) { create(:user, :admin) }

  before { sign_in user }

  it 'GET /admin/baserow_schema redirige vers /admin/schema_builder_legacy' do
    get '/admin/baserow_schema'
    expect(response).to redirect_to('/admin/schema_builder_legacy')
  end

  it 'GET /admin/baserow_schema/repetable_blocks redirige' do
    get '/admin/baserow_schema/repetable_blocks'
    expect(response).to redirect_to('/admin/schema_builder_legacy')
  end

  it 'GET /admin/grist_schema redirige' do
    get '/admin/grist_schema'
    expect(response).to redirect_to('/admin/schema_builder_legacy')
  end

  it 'GET /admin/grist_schema/repetable_blocks redirige' do
    get '/admin/grist_schema/repetable_blocks'
    expect(response).to redirect_to('/admin/schema_builder_legacy')
  end

  it 'GET /admin/schema_builder_legacy retourne 200 et liste les démarches' do
    create(:demarche)
    get '/admin/schema_builder_legacy'
    expect(response).to have_http_status(:ok)
  end
end
