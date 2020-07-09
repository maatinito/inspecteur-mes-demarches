# frozen_string_literal: true

class Message < ApplicationRecord
  belongs_to :check

  def hashkey
    message + value + field
  end
end
