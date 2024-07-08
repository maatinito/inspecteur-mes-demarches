# frozen_string_literal: true

# == Schema Information
#
# Table name: bookings
#
#  id         :bigint           not null, primary key
#  dossier    :integer
#  user       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  session_id :bigint
#
# Indexes
#
#  index_bookings_on_dossier_and_user_and_session_id  (dossier,user,session_id) UNIQUE
#  index_bookings_on_session_id                       (session_id)
#
class Booking < ApplicationRecord
  belongs_to :session, counter_cache: true
end
