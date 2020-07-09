# frozen_string_literal: true

class AddPostedToCheck < ActiveRecord::Migration[5.2]
  def change
    add_column :checks, :posted, :boolean, default: false
  end
end
