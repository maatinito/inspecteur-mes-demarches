# frozen_string_literal: true

# == Schema Information
#
# Table name: demarches
#
#  id            :bigint           not null, primary key
#  checked_at    :datetime
#  configuration :string
#  instructeur   :string
#  libelle       :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class Demarche < ApplicationRecord
  has_many :checks, dependent: :destroy
end
