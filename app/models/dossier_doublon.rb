# frozen_string_literal: true

# == Schema Information
#
# Table name: dossier_doublons
#
#  id                            :bigint           not null, primary key
#  cle                           :string           not null
#  date_passage_en_construction  :datetime
#  demarche_id                   :integer          not null
#  dossier_number                :integer          not null
#  state                         :string           not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#
# Indexes
#
#  index_dossier_doublons_on_demarche_id_and_cle  (demarche_id,cle)
#  index_dossier_doublons_on_dossier_number       (dossier_number) UNIQUE
#
class DossierDoublon < ApplicationRecord
  validates :demarche_id, presence: true
  validates :dossier_number, presence: true, uniqueness: true
  validates :cle, presence: true
  validates :state, presence: true

  scope :for_demarche, ->(demarche_id) { where(demarche_id:) }
  scope :with_states, ->(states) { where(state: states) }
  scope :recent, ->(months) { months.present? ? where(date_passage_en_construction: months.months.ago..) : all }

  def self.duplicates_of(demarche_id:, cle:, dossier_number:, etats:, purge_after_months: nil)
    for_demarche(demarche_id)
      .with_states(etats)
      .where(cle:)
      .where.not(dossier_number:)
      .recent(purge_after_months)
      .order(:dossier_number)
  end
end
