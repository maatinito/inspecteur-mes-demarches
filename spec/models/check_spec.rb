# frozen_string_literal: true

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
