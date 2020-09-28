# frozen_string_literal: true

require 'rails_helper'
# require 'app/lib/inspector_task'

RSpec.describe InspectorTask do
  class TestTask < InspectorTask
    def required_fields
      super + %i[required]
    end

    def authorized_fields
      super + %i[optional]
    end
  end
  context 'with unknown fields' do
    subject { TestTask.new({ unknown: 'value', required: '' }) }
    it 'should be invalid' do
      expect(subject.valid?).to be_falsey
      expect(subject.errors).to include("unknown n'existe(nt) pas sur test_task")
    end
  end

  context 'with only mandatory fields' do
    subject { TestTask.new({ required: '' }) }
    it 'should be valid' do
      expect(subject.valid?).to be true
      expect(subject.errors).to be_empty
    end
  end

  context 'with optional fields' do
    subject { TestTask.new({ required: '', optional: 'optional' }) }
    it 'should be valid' do
      expect(subject.valid?).to be true
      expect(subject.errors).to be_empty
    end
  end

  context 'with missing mandatory fields' do
    subject { TestTask.new({ optional: '' }) }
    it 'should be valid' do
      puts subject.errors
      expect(subject.valid?).to be false
      expect(subject.errors).to include('Les champs required devrait être définis sur test_task')
    end
  end
end
