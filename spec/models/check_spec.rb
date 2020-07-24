# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Check, type: :model do
  let(:check) { Check.new }
  let(:msg) { Message.new(field: 'dossier', value: '33', message: 'message') }

  describe '#add_message' do
    it 'should store messages' do
      check.messages << msg
      expect(check.messages.size).to be_equal(1)
    end
  end
end
