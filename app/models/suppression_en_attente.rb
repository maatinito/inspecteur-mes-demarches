# frozen_string_literal: true

# == Schema Information
#
# Table name: suppressions_en_attente
#
#  id          :bigint           not null, primary key
#  dossier     :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  demarche_id :bigint           not null
#
# Indexes
#
#  index_suppressions_en_attente_on_demarche_id_and_dossier  (demarche_id,dossier) UNIQUE
#
# Dossier supprimé dont au moins une tâche n'a pas pu traiter la suppression (hook `deleted`).
# Rejoué à chaque passage du moteur jusqu'à ce que toutes les tâches réussissent.
class SuppressionEnAttente < ApplicationRecord
  self.table_name = 'suppressions_en_attente'

  belongs_to :demarche
end
