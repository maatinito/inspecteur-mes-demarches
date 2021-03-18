# frozen_string_literal: true

class CreateJoinTableDemarcheUser < ActiveRecord::Migration[6.1]
  def change
    create_join_table :demarches, :users do |t|
      # t.index [:demarche_id, :user_id]
      t.index %i[user_id demarche_id]
    end
  end
end
