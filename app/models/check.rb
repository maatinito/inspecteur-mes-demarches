class Check < ApplicationRecord
  has_many :messages, dependent: :destroy
  belongs_to :demarche
end
