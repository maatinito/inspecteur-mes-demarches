class Demarche < ApplicationRecord
  has_many :checks, dependent: :destroy
end
