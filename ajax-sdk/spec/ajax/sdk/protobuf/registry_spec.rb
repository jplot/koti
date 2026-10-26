# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Protobuf::Registry do
  subject(:registry) { described_class.from_descriptor_set(File.binread(fixture)) }

  let(:fixture) { File.join(__dir__, '../../../fixtures/protobuf/sample.pb') }

  it 'decodes a real FileDescriptorSet with DESCRIPTOR' do
    expect(registry.message('koti.sample.Sample').fields.map { [it.name, it.number] })
      .to eq([[:a, 1], [:numbers, 2], [:counts, 3], [:scalars, 4], [:items, 5], [:name, 6], [:level, 7], [:maybe, 8]])
  end

  it 'marks proto3 repeated scalars as packed' do
    expect(registry.message('koti.sample.Sample').fields.find { it.name == :numbers }.packed).to be(true)
  end

  it 'marks a nested map entry' do
    expect(registry.message('koti.sample.Sample.CountsEntry').map_entry).to be(true)
  end

  it 'reads an enum' do
    expect(registry.enum('koti.sample.Level').values).to eq(0 => :LEVEL_UNSPECIFIED, 1 => :LEVEL_LOW, 2 => :LEVEL_HIGH)
  end

  it 'raises on an unknown message' do
    expect { registry.message('koti.sample.Nope') }.to raise_error(ArgumentError, /koti.sample.Nope/)
  end
end
