# frozen_string_literal: true

class AddFailedToChecks < ActiveRecord::Migration[5.2]
  def change
    add_column :checks, :failed, :boolean, default: false
  end
end
