# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Demarche, type: :model do
  describe 'associations' do
    it 'has_many schema_targets dependent destroy' do
      assoc = described_class.reflect_on_association(:schema_targets)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end

    it 'destroy d\'une démarche cascade sur ses schema_targets' do
      demarche = create(:demarche)
      create(:schema_target, demarche: demarche)
      expect { demarche.destroy }.to change(SchemaTarget, :count).by(-1)
    end
  end
end
