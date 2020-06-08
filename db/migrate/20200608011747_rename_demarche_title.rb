class RenameDemarcheTitle < ActiveRecord::Migration[5.2]
  def change
    rename_column :demarches, :title, :libelle
  end
end
