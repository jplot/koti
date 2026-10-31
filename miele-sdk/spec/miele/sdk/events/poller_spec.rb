# frozen_string_literal: true

RSpec.describe Miele::Sdk::Events::Poller do
  subject(:poller) do
    described_class.new(appliance, Miele::Sdk::Objects::Oven::GlobalDeviceCombiState, [2, 1586, 0, 0],
                        sleeper: ->(seconds) { log << [:wait, seconds] })
  end

  let(:log) { [] }
  let(:values) { [1, 1, 2, 2, 3] }
  let(:appliance) do
    readings = values
    events = log
    Object.new.tap do |fake|
      fake.define_singleton_method(:object) do |klass, address|
        events << [:read, address]
        klass.from({ 1 => Miele::Sdk::Dop2::Field.new(type: :e8, value: readings.shift || 3) })
      end
    end
  end

  def states(count)
    received = []
    poller.each do |value|
      received << Miele::Sdk::Objects::Oven::GlobalEnumApplianceState.to_i(value.appliance_state)
      break if received.size == count
    end
    received
  end

  it 'polls every 3 s after the previous read ends, as the app does' do
    states(2)
    expect(log).to eq([[:read, [2, 1586, 0, 0]], [:wait, 3], [:read, [2, 1586, 0, 0]], [:wait, 3],
                       [:read, [2, 1586, 0, 0]]])
  end

  it 'yields only changes' do
    expect(states(3)).to eq([1, 2, 3])
  end

  it 'stops when the block breaks' do
    states(1)
    expect(log.count { it.first == :read }).to eq(1)
  end
end
