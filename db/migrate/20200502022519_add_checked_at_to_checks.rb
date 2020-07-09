# frozen_string_literal: true

class AddCheckedAtToChecks < ActiveRecord::Migration[5.2]
  def change
    add_column :checks, :checked_at, :datetime
  end
end
