# frozen_string_literal: true

# == Schema Information
#
# Table name: dossier_doublons
#
#  id             :bigint           not null, primary key
#  cle            :string           not null
#  depose_at      :datetime         not null
#  dossier_number :integer          not null
#  state          :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  demarche_id    :integer          not null
#
# Indexes
#
#  index_dossier_doublons_on_demarche_id_and_cle_and_depose_at  (demarche_id,cle,depose_at)
#  index_dossier_doublons_on_dossier_number                     (dossier_number) UNIQUE
#
class DossierDoublon < ApplicationRecord
  validates :demarche_id, presence: true
  validates :dossier_number, presence: true, uniqueness: true
  validates :cle, presence: true
  validates :state, presence: true
  validates :depose_at, presence: true

  scope :for_demarche, ->(demarche_id) { where(demarche_id:) }
  scope :with_states, ->(states) { where(state: states) }
  scope :recent, ->(months) { months.present? ? where(depose_at: months.months.ago..) : all }

  # Asymétrique : ne renvoie que les frères ANTÉRIEURS au dépôt légal (depose_at).
  # Le dossier déposé en premier reste légitime ; ceux déposés après sont marqués doublons.
  def self.duplicates_of(demarche_id:, cle:, depose_at:, etats:, purge_after_months: nil)
    for_demarche(demarche_id)
      .with_states(etats)
      .where(cle:)
      .where('depose_at < ?', depose_at)
      .recent(purge_after_months)
      .order(:depose_at, :dossier_number)
  end

  # Pendant asymétrique : numéros des dossiers POSTÉRIEURS sur les mêmes clés.
  # Utilisé pour réveiller les "candidats doublons" quand le statut du légitime change
  # (clé modifiée, sortie du registre).
  def self.posterior_siblings(demarche_id:, cles:, depose_at:)
    return [] if cles.empty? || depose_at.blank?

    for_demarche(demarche_id)
      .where(cle: cles)
      .where('depose_at > ?', depose_at)
      .pluck(:dossier_number)
  end
end
