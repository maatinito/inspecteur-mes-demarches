class AddInstructeurToDemarche < ActiveRecord::Migration[5.2]
  def change
    add_column :demarches, :instructeur, :string
  end
end
