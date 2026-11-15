# frozen_string_literal: true

RSpec.describe Miele::Sdk::Appliance do
  subject(:appliance) { described_class.new('127.0.0.1', fab:, sleeper: ->(seconds) { waits << seconds }) }

  let(:fab) { '000123456789' }
  let(:answers) { [] }
  let(:fake) do
    queued = answers
    FakeAppliance.start { queued.shift || [204, {}, ''] }
  end

  before { connect_to(fake) }

  after { fake.stop }

  def waits = @waits ||= []

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
