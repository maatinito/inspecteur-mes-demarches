class ChangeCheckDemarche < ActiveRecord::Migration[5.2]
  def change
    rename_column :checks, :demarche, :demarche_id
  end
end
