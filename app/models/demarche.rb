# frozen_string_literal: true

class Demarche < ApplicationRecord
  has_many :checks, dependent: :destroy
end
