# frozen_string_literal: true

require 'rspec'

describe 'Excel::Group' do
  let(:fields) do
    { 'my_array' => [
      { 'k1' => 1, 'k2' => 2, 'k3' => 1.0 },
      { 'k1' => 1, 'k2' => 2, 'k3' => 2.0 },
      { 'k1' => 2, 'k2' => 2, 'k3' => 3.0 }
    ] }
  end
  let(:result) do
    { 'my_array' => [
      { 'k1' => 1, 'k2' => 2, 'k3' => '1.0, 2.0' },
      { 'k1' => 2, 'k2' => 2, 'k3' => 3.0 }
    ] }
  end

  subject do
    controle.process_row(nil, fields)
    fields
  end

  context 'colonnes_as_string' do
    let(:controle) { FactoryBot.build :excel_group }
    it 'merge lines on k1,k2' do
      expect(subject).to match(result)
    end
  end

  context 'colonnes_as_list' do
    let(:controle) { FactoryBot.build :excel_group, :colonnes_as_list }
    it 'merge lines on k1,k2' do
      expect(subject).to match(result)
    end
  end
end
