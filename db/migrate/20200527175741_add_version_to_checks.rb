# frozen_string_literal: true

class AddVersionToChecks < ActiveRecord::Migration[5.2]
  def change
    add_column :checks, :version, :float, default: 1.0
  end
end
