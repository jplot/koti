# frozen_string_literal: true

RSpec.describe Miele::Sdk::Hood do
  subject(:hood) { described_class.new('127.0.0.1', ident:, sleeper: ->(seconds) { waits << seconds }, clock:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 18, 'ProtocolVersion' => 2) }
  let(:plus) do
    { 'available' => true, 'activated' => false, 'availableSourceDeviceIds' => %w[000111222333 000444555666],
      'sourceDeviceIds' => [] }
  end
  let(:color_flow) { [200, {}, '{"active":false,"intervalDurationSeconds":10}'] }
  let(:fake) do
    services = JSON.generate('ConnectivityPlus' => plus)
    supervised = '{"Show":false,"Signal":false}'
    flow = color_flow
    queued = refusals
    side = hood_side
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: %r{/services\z} } then [200, {}, services]
      in { verb: 'GET', path: %r{/SuperVision/\d+\z} } then [200, {}, supervised]
      in { verb: 'PUT' } if (refusal = queued.shift) then refusal
      in { verb: 'PUT', path: %r{/services/ConnectivityPlus\z} } if side[:applies]
        services = JSON.generate('ConnectivityPlus' => JSON.parse(request.body))
        [200, {}, '{}']
      in { verb: 'PUT', path: %r{/SuperVision/\d+\z} } if side[:applies]
        supervised = request.body
        [200, {}, '{}']
      in { path: %r{/ColorFlow\z} } then flow
      else [200, {}, '{}']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def written = fake.requests.reject { it.verb == 'GET' }.map { [it.verb, it.path, JSON.parse(it.body)] }

  def waits = @waits ||= []

  def clock = -> { waits.sum + (fake.requests.size * round_trip) }

  def round_trip = 0

  def refusals = @refusals ||= []

  def hood_side = @hood_side ||= { applies: true }

  def gets(path) = fake.requests.count { it.verb == 'GET' && it.path.end_with?(path) }

  def plus_requests = fake.requests.map { [it.verb, it.path[/services.*/]] }.select(&:last)

  it 'reads Con@ctivity Plus from services' do
    expect(hood.connectivity_plus).to eq(described_class::ConnectivityPlus.new(
                                           available: true, activated: false,
                                           available_sources: %w[000111222333 000444555666], sources: []
                                         ))
  end

  it 'follows one more hob, activating Con@ctivity Plus as the app does' do
    hood.connect_hob('000111222333')
    expect(written).to eq([['PUT', "/Devices/#{fab}/services/ConnectivityPlus",
                            { 'activated' => true, 'sourceDeviceIds' => %w[000111222333] }]])
  end

  it 'writes Con@ctivity Plus again 2 s after a 5xx or a lost connection, four times at most, reading services ' \
     'again once their last answer is 3 s old', :aggregate_failures do
    refusals.push([500, {}, ''], :drop, [503, {}, ''], [500, {}, ''])
    expect { hood.connect_hob('000111222333') }.to raise_error(Miele::Sdk::ResponseError, 'appliance answered 500')
    expect(plus_requests.map(&:first)).to eq(%w[GET PUT PUT GET PUT PUT])
    expect(waits).to eq([2, 2, 2])
  end

  it 'reads services 1 s after a write the second attempt sent 2 s after the read it reuses', :aggregate_failures do
    refusals.push([500, {}, ''])
    hood.connect_hob('000111222333')
    expect(plus_requests.map(&:first)).to eq(%w[GET PUT PUT GET])
    expect(waits).to eq([2, 1])
  end

  it 'reads nothing more when the services it wrote from already show the hob as written', :aggregate_failures do
    hood.disconnect_hob('000111222333')
    expect(plus_requests.map(&:first)).to eq(%w[GET PUT])
    expect(waits).to be_empty
  end

  it 'reads services 3 s after its write, as the read polled before it, until they show the hob as written',
     :aggregate_failures do
    hood.connect_hob('000111222333')
    expect(fake.requests.map { [it.verb, it.path[/services.*/]] }.select(&:last))
      .to eq([%w[GET services], %w[PUT services/ConnectivityPlus], %w[GET services]])
    expect(waits).to eq([3])
  end

  it 'reads services every 3 s and raises ActionFailedError once the 15 s are up', :aggregate_failures do
    hood_side[:applies] = false
    expect { hood.connect_hob('000111222333') }.to raise_error(Miele::Sdk::ActionFailedError)
    expect([gets('/services'), waits]).to eq([5, [3, 3, 3, 3]])
  end

  it 'reads SuperVision back at once, then every 3 s, within the 15 s its write retries also take',
     :aggregate_failures do
    refusals.push([502, {}, ''], [503, {}, ''])
    hood_side[:applies] = false
    expect { hood.supervise('000111222333', show: true) }.to raise_error(Miele::Sdk::ActionFailedError)
    expect([gets('/SuperVision/000111222333'), waits]).to eq([4, [2, 2, 3, 3, 3]])
  end

  context 'when each round trip takes a second' do
    def round_trip = 1

    it 'counts them in the 15 s, which then leave room for four reads of SuperVision', :aggregate_failures do
      hood_side[:applies] = false
      expect { hood.supervise('000111222333', show: true) }.to raise_error(Miele::Sdk::ActionFailedError)
      expect([gets('/SuperVision/000111222333'), waits]).to eq([4, [3, 3, 3]])
    end

    it 'gives each of its requests only what the 15 s have left', :aggregate_failures do
      Miele::Sdk.config.read_timeout = 30
      timeouts = read_timeouts
      hood_side[:applies] = false
      expect { hood.supervise('000111222333', show: true) }.to raise_error(Miele::Sdk::ActionFailedError)
      expect(timeouts.drop(1)).to eq([15, 14, 10, 6, 2])
    end

    it 'gives each Con@ctivity Plus request only what the 15 s have left', :aggregate_failures do
      Miele::Sdk.config.read_timeout = 30
      hood.fab
      timeouts = read_timeouts
      refusals.push(*[[500, {}, '']] * 4)
      expect { hood.connect_hob('000111222333') }.to raise_error(Miele::Sdk::ResponseError)
      expect(timeouts).to eq([15, 14, 11, 10, 7, 6, 3, 2])
    end
  end

  context 'when the services read takes the 15 s' do
    def round_trip = 15

    it 'sends no write once its token is cancelled', :aggregate_failures do
      hood.fab
      expect { hood.connect_hob('000111222333') }.to raise_error(Miele::Sdk::ActionFailedError, /ran out/)
      expect(plus_requests).to eq([%w[GET services]])
    end
  end

  it 'shows an appliance under Con@ctivity One, its Signal left out as the app leaves it' do
    hood.supervise('000111222333', show: true)
    expect(written).to eq([['PUT', "/Devices/#{fab}/SuperVision/000111222333", { 'Show' => true }]])
  end

  it 'raises Con@ctivity One refused a fourth time, as its helper retries three times', :aggregate_failures do
    refusals.push(*[[502, {}, '']] * 4)
    expect { hood.supervise('000111222333', show: true) }.to raise_error(Miele::Sdk::ResponseError)
    expect([written.size, waits]).to eq([4, [2, 2, 2]])
  end

  it 'writes Con@ctivity One again 2 s after a 5xx, and a 4xx at once', :aggregate_failures do
    refusals.push([502, {}, ''], [404, {}, ''])
    expect { hood.supervise('000111222333', show: true) }.to raise_error(Miele::Sdk::NotFoundError)
    expect(written.map { it[1] }).to eq(["/Devices/#{fab}/SuperVision/000111222333"] * 2)
    expect(waits).to eq([2])
  end

  it 'sets ColorFlow with its interval in seconds, one the app does not offer too', :aggregate_failures do
    expect(hood.color_flow_intervals).to eq([5, 10, 20])
    hood.configure_color_flow(active: true, interval: 20)
    hood.configure_color_flow(active: true, interval: 15)
    expect(written.map { it.last['intervalDurationSeconds'] }).to eq([20, 15])
  end

  context 'when the hood has no ColorFlow' do
    let(:color_flow) { [404, {}, ''] }

    it 'lets a local 404 through, which a module that does not serve ColorFlow answers too' do
      expect { hood.configure_color_flow(active: true) }.to raise_error(Miele::Sdk::NotFoundError)
    end

    it 'sends ColorFlow to a hood the cloud says has none, and raises its 404', :aggregate_failures do
      cloud = instance_double(Miele::Sdk::Cloud::Channel)
      allow(cloud).to receive(:request).and_raise(Miele::Sdk::NotFoundError.new(404))
      reached = described_class.new('127.0.0.1', ident:, fab:, cloud:)
      expect(reached.color_flow).to be_nil
      expect { reached.configure_color_flow(active: true) }.to raise_error(Miele::Sdk::NotFoundError)
    end
  end

  context 'when the hood follows a hob' do
    let(:plus) { { 'available' => true, 'activated' => true, 'sourceDeviceIds' => %w[000111222333] } }

    it 'stops following it, deactivating Con@ctivity Plus once none is left' do
      hood.disconnect_hob('000111222333')
      expect(written).to eq([['PUT', "/Devices/#{fab}/services/ConnectivityPlus",
                              { 'activated' => false, 'sourceDeviceIds' => [] }]])
    end
  end

  context 'when the hood does not offer Con@ctivity Plus' do
    let(:plus) { { 'available' => false } }

    it 'follows a hob, while Con@ctivity Plus tells the app does not offer it', :aggregate_failures do
      expect(hood.connectivity_plus.available).to be(false)
      hood.connect_hob('000111222333')
      expect(written.map { it.last['sourceDeviceIds'] }).to eq([%w[000111222333]])
    end
  end
end
