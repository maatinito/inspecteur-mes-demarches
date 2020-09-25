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
#  posted      :boolean          default(FALSE)
#  version     :float            default(1.0)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  demarche_id :integer
#
# Indexes
#
#  by_dossier  (dossier)
#  unicity     (dossier,checker) UNIQUE
#
require 'rails_helper'

RSpec.describe Check, type: :model do
  let(:check) { create :check_with_messages }
  let(:msg) { Message.new(field: 'dossier', value: '33', message: 'message') }

  describe '#add_message' do
    it 'should store messages' do
      check.messages << msg
      expect(check.messages.size).to be_equal(2)
      expect(check.save).to be_truthy
    end
  end
end
