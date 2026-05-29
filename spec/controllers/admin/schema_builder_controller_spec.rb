# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::SchemaBuilderController, type: :controller do
  let(:user) { create(:user) }
  let(:demarche) { create(:demarche) }

  before { sign_in user }

  describe 'GET #show' do
    it 'rend la page (200)' do
      get :show, params: { demarche_demarche_id: demarche.id }
      expect(response).to have_http_status(:ok)
    end

    it 'assigne @demarche' do
      get :show, params: { demarche_demarche_id: demarche.id }
      expect(controller.instance_variable_get(:@demarche)).to eq(demarche)
    end

    it 'assigne @schema_targets (vide initialement)' do
      get :show, params: { demarche_demarche_id: demarche.id }
      expect(controller.instance_variable_get(:@schema_targets)).to eq([])
    end

    it "404 si la démarche n'existe pas" do
      expect { get :show, params: { demarche_demarche_id: 99_999 } }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
