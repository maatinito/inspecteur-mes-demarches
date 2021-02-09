# frozen_string_literal: true

# == Schema Information
#
# Table name: messages
#
#  id         :bigint           not null, primary key
#  field      :string
#  message    :string
#  value      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  check_id   :bigint
#
# Indexes
#
#  index_messages_on_check_id  (check_id)
#
class Message < ApplicationRecord
  belongs_to :check

  def hashkey
    (message||'') + value + field
  end

  def ==(other)
    message == other.message &&
      field == other.field &&
      value == other.value
  end
end
