class AddConfigurationToDemarches < ActiveRecord::Migration[5.2]
  def change
    add_column :demarches, :configuration, :string
  end
end
