# frozen_string_literal: true

require 'rspec'

describe 'Excel::Partition' do
  let(:fields) do
    { 'my_array' => [
      { 'k1' => 1, 'k2' => 2, 'k3' => 1.0 },
      { 'k1' => 1, 'k2' => 2, 'k3' => 2.0 },
      { 'k1' => 2, 'k2' => 2, 'k3' => 3.0 }
    ] }
  end
  let(:result) do
    fields.merge({ 'my_array.1' => [{ 'k1' => 1, 'k2' => 2, 'k3' => 1.0 }, { 'k1' => 1, 'k2' => 2, 'k3' => 2.0 }],
                   'my_array.2' => [{ 'k1' => 2, 'k2' => 2, 'k3' => 3.0 }] })
  end
  let(:controle) { FactoryBot.build :excel_partition }

  subject do
    controle.process_row(nil, fields)
    fields
  end

  it 'partitions lines on k1 key' do
    expect(subject).to match(result)
  end
end
