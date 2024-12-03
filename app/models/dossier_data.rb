# frozen_string_literal: true

# == Schema Information
#
# Table name: dossier_data
#
#  id         :bigint           not null, primary key
#  data       :jsonb            not null
#  dossier    :integer          not null
#  label      :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_dossier_data_on_dossier_and_label  (dossier,label) UNIQUE
#
class DossierData < ApplicationRecord
  validates :dossier, presence: true, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1_000_000 }
  validates :label, presence: true, uniqueness: { scope: :dossier }
  validates :data, presence: true

  # Index pour accélérer les recherches
  def self.find_by_folder_and_label(dossier, label)
    find_by(dossier:, label:)
  end
end
