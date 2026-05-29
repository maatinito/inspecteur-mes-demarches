# frozen_string_literal: true

module Admin
  class SchemaBuilderController < ApplicationController
    before_action :authenticate_user!
    before_action :set_demarche

    def show
      @schema_targets = @demarche.schema_targets.order(:target_type)
    end

    private

    def set_demarche
      @demarche = Demarche.find(params[:demarche_demarche_id])
    end
  end
end
