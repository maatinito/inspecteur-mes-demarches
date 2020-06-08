class CreateDemarches < ActiveRecord::Migration[5.2]
  def change
    create_table :demarches do |t|
      t.string :libelle
      t.timestamp :checked_at

      t.timestamps
    end
  end
end
