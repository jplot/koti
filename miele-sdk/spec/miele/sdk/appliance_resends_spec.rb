# frozen_string_literal: true

RSpec.describe Miele::Sdk::Appliance do
  subject(:appliance) { described_class.new('127.0.0.1', fab:, sleeper: ->(seconds) { waits << seconds }, clock:) }

  let(:fab) { '000123456789' }
  let(:answers) { [] }
  let(:fake) do
    queued = answers
    FakeAppliance.start { queued.shift || [204, {}, ''] }
  end

  before { connect_to(fake) }

  after { fake.stop }

  def waits = @waits ||= []

  def clock = -> { waits.sum + (fake.requests.size * round_trip) }

  def round_trip = 0

  def sent = fake.requests.map { [it.verb, it.path.delete_prefix("/Devices/#{fab}/")] }

  it 'renames it again 1.5^n s after a 5xx or a dropped connection, as ChangeApplianceNameAction does',
     :aggregate_failures do
    answers.push([500, {}, ''], :drop)
    appliance.name = 'Cuisine'
    expect(sent).to eq([%w[PUT Ident]] * 3)
    expect(waits).to eq([1.5, 2.25])
  end

  it 'gives up renaming once the next wait would pass its 15 s ActionExecutionTimeout', :aggregate_failures do
    answers.concat([[503, {}, '']] * 9)
    expect { appliance.name = 'Cuisine' }.to raise_error(Miele::Sdk::ResponseError, 'appliance answered 503')
    expect(sent).to eq([%w[PUT Ident]] * 5)
    expect(waits).to eq([1.5, 2.25, 3.375, 5.0625])
  end

  context 'when each round trip takes a second' do
    def round_trip = 1

    it 'counts them in the 15 s, which then leave room for four attempts', :aggregate_failures do
      answers.concat([[503, {}, '']] * 9)
      expect { appliance.name = 'Cuisine' }.to raise_error(Miele::Sdk::ResponseError, 'appliance answered 503')
      expect(sent).to eq([%w[PUT Ident]] * 4)
      expect(waits).to eq([1.5, 2.25, 3.375])
    end

    it 'gives each attempt only what the 15 s have left, as the app cancels its token then', :aggregate_failures do
      Miele::Sdk.config.read_timeout = 30
      timeouts = read_timeouts
      answers.concat([[503, {}, '']] * 9)
      expect { appliance.name = 'Cuisine' }.to raise_error(Miele::Sdk::ResponseError)
      expect(timeouts).to eq([15, 12.5, 9.25, 4.875])
    end
  end

  context 'when the appliance answers after what the 15 s leave' do
    let(:fake) { FakeAppliance.start { sleep(1) && [204, {}, ''] } }

    def clock
      now = Miele::Sdk::Resends::MONOTONIC
      started = nil
      -> { started ? 14.8 + now.call - started : (started = now.call) && 0.0 }
    end

    it 'raises ActionFailedError, the timed-out connection as its cause, as the Timeout fails the action',
       :aggregate_failures do
      expect { appliance.name = 'Cuisine' }
        .to raise_error(Miele::Sdk::ActionFailedError) { expect(it.cause).to be_a(Miele::Sdk::ConnectionError) }
    end

    it 'raises ConnectionError when the request runs out of its own timeout first' do
      Miele::Sdk.config.read_timeout = 0.1
      expect { appliance.name = 'Cuisine' }.to raise_error(Miele::Sdk::ConnectionError)
    end
  end

  it 'raises a 4xx to a rename at once', :aggregate_failures do
    answers.push([400, {}, ''])
    expect { appliance.name = 'Cuisine' }.to raise_error(Miele::Sdk::ResponseError, 'appliance answered 400')
    expect([sent.size, waits]).to eq([1, []])
  end

  it 'reads Con@ctivity One back on an oven too, whose own polling is another' do
    answers.push([204, {}, ''], [200, {}, '{"Show":true}'])
    ident = Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 12, 'ProtocolVersion' => 4)
    Miele::Sdk::Oven.new('127.0.0.1', fab:, ident:).supervise('000111222333', show: true)
    expect(sent).to eq([%w[PUT SuperVision/000111222333], %w[GET SuperVision/000111222333]])
  end
end
