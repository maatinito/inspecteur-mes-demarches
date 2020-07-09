# frozen_string_literal: true

class AddDemarcheToChecks < ActiveRecord::Migration[5.2]
  def change
    add_column :checks, :demarche, :integer
  end
end
