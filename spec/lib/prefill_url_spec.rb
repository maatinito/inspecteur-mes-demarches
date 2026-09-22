# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PrefillURL do
  before { allow(MesDemarches).to receive(:public_url).and_return('https://www.mes-demarches.gov.pf') }

  it 'encode chaque champ en champ_<Base64(Champ-<stable_id>)>=<valeur>' do
    url = described_class.build('engagements-poussins', { 197_027 => 654_125, 197_038 => 'Manutere TERE' })
    expect(url).to eq 'https://www.mes-demarches.gov.pf/commencer/engagements-poussins' \
                      '?champ_Q2hhbXAtMTk3MDI3=654125&champ_Q2hhbXAtMTk3MDM4=Manutere+TERE'
  end

  it 'formate les dates et dates-heures en ISO 8601 (jour seul)' do
    url = described_class.build('p', { 1 => DateValue.new(2026, 9, 30), 2 => DatetimeValue.new(2026, 10, 1, 1, 30) })
    expect(url).to include('=2026-09-30', '=2026-10-01')
  end

  it 'ignore les valeurs nulles ou vides et encode le padding Base64 de la clé' do
    url = described_class.build('p', { 1 => nil, 2 => '  ', 65_381 => 12 })
    expect(url).to eq 'https://www.mes-demarches.gov.pf/commencer/p?champ_Q2hhbXAtNjUzODE%3D=12'
  end

  it 'joint un tableau de valeurs par une virgule' do
    expect(described_class.build('p', { 1 => %w[Ponte Chair] })).to end_with('=Ponte%2C+Chair')
  end
end
