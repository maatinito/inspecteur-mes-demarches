# frozen_string_literal: true

# == Schema Information
#
# Table name: checks
#
#  id          :bigint           not null, primary key
#  checked_at  :datetime
#  checker     :string
#  dossier     :integer
#  failed      :boolean
#  failed_at   :datetime
#  posted      :boolean          default(FALSE)
#  version     :bigint           default(1)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  demarche_id :integer
#
# Indexes
#
#  by_dossier  (dossier)
#  unicity     (dossier,checker) UNIQUE
#
class Check < ApplicationRecord
  has_many :messages, dependent: :destroy
  belongs_to :demarche
end
