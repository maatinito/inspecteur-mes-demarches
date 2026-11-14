# frozen_string_literal: true

# == Schema Information
#
# Table name: suppressions_en_attente
#
#  id          :bigint           not null, primary key
#  dossier     :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  demarche_id :bigint           not null
#
# Indexes
#
#  index_suppressions_en_attente_on_demarche_id_and_dossier  (demarche_id,dossier) UNIQUE
#
require 'rails_helper'

RSpec.describe SuppressionEnAttente do
  let(:demarche) { create(:demarche) }

  it 'refuse un doublon (démarche, dossier)' do
    described_class.create!(demarche:, dossier: 12)

    expect { described_class.create!(demarche:, dossier: 12) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(described_class.new(demarche:, dossier: 13)).to be_valid
  end

  it 'exige une démarche et un dossier' do
    expect(described_class.new).not_to be_valid
  end
end
