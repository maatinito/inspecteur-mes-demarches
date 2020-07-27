# frozen_string_literal: true

require 'spec_helper'
# require 'app/lib/inspector_task'

RSpec.describe FieldChecker do
  class TestFieldChecker < FieldChecker
    def check(dossier)
      pp dossier
      add_message('field', 'value', 'message') if @params[:fail]
    end

    def required_fields
      super + %i[fail]
    end
  end

  let(:dossier) { FactoryBot.build(:dossier) }

  subject { TestFieldChecker.new({ fail: failed }) }

  before do
    subject.control(dossier)
  end

  context 'check succeed' do
    let(:failed) { false }

    it 'should have no message' do
      expect(subject.messages).to be_empty
    end
  end

  context 'check failed' do
    let(:failed) { true }

    it 'should have one message' do
      expect(subject.messages.size).to be 1
    end
  end
end
