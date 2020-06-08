class AddOriginToMessages < ActiveRecord::Migration[5.2]
  def change
    add_column :messages, :field, :string
    add_column :messages, :value, :string
  end
end
