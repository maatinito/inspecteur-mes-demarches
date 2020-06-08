class RenameDemarcheLibelle < ActiveRecord::Migration[5.2]
  def change
    rename_column :demarches, :libelle, :title
  end
end
