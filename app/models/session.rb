# frozen_string_literal: true

# == Schema Information
#
# Table name: sessions
#
#  id             :bigint           not null, primary key
#  bookings_count :integer          default(0), not null
#  capacity       :integer
#  date           :datetime
#  name           :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_sessions_on_name_and_date  (name,date) UNIQUE
#
class Session < ApplicationRecord
  has_many :bookings
end
