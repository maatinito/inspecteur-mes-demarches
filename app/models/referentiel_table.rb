# frozen_string_literal: true

# == Schema Information
#
# Table name: referentiel_tables
#
#  id           :bigint           not null, primary key
#  alerte_le    :datetime
#  backend      :string           not null
#  mode         :string           not null
#  proprietaire :bigint
#  refus_depuis :datetime
#  table_ref    :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_referentiel_tables_on_backend_and_table_ref  (backend,table_ref) UNIQUE
#
# Type figé d'une table de référentiel (Baserow ou Grist) : mode d'exploitation et propriétaire
# mémorisés à la première lecture, pour détecter une modification du marqueur.
class ReferentielTable < ApplicationRecord
  MODES = %w[archive dlnuf].freeze

  validates :backend, :table_ref, :mode, presence: true
  validates :mode, inclusion: { in: MODES }
  validates :table_ref, uniqueness: { scope: :backend }

  def dlnuf?
    mode == 'dlnuf'
  end
end
