# frozen_string_literal: true

RSpec.describe Miele::Sdk::Events::Event do
  def event(resource, content) = described_class.new(fab: '000111222333', resource:, content:)

  it 'reads a pushed state as a typed value' do
    expect(event('/State/', { 'Status' => 5, 'Light' => 1 }).attributes)
      .to eq(Miele::Sdk::Schema::DeviceState.new(status: 5, light: 1))
  end

  it 'reads the part of the state a sub-resource pushes' do
    expect(event('/State/Light/', { 'Light' => 2 }).attributes).to eq(Miele::Sdk::Schema::DeviceState.new(light: 2))
  end

  it 'reads a pushed identification as a typed value' do
    expect(event('/Ident/', { 'DeviceType' => 18, 'ProtocolVersion' => 2 }).attributes)
      .to be_a(Miele::Sdk::Schema::DeviceIdentification).and(have_attributes(device_type: 18, protocol_version: 2))
  end

  it 'has no typed value for a DOP2 leaf or the device list the cloud pushes' do
    leaf = Miele::Sdk::Dop2::Leaf.new(unit: 2, attribute: 1586, idx1: 0, idx2: 0, fields: [])
    expect([event('/DOP2/2/1586/', leaf).attributes, event('/Devices/', [{ 'Fab' => '000111222333' }]).attributes])
      .to eq([nil, nil])
  end
end
