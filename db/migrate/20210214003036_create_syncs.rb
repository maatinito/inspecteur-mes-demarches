# frozen_string_literal: true

class CreateSyncs < ActiveRecord::Migration[6.1]
  def change
    create_table :syncs do |t|
      t.string :job

      t.timestamps
    end
  end
end
