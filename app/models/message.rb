# frozen_string_literal: true

class Message < ApplicationRecord
  belongs_to :check

  def hashkey
    message + value + field
  end

  def ==(other)
    message == other.message &&
      field == other.field &&
      value == other.value
  end
end
