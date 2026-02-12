# frozen_string_literal: true

class AddFailedAtToChecks < ActiveRecord::Migration[7.2]
  def change
    add_column :checks, :failed_at, :datetime
  end
end
