# frozen_string_literal: true

RSpec.describe Miele::Sdk::Oven do
  subject(:oven) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 13, 'ProtocolVersion' => 4) }
  let(:state) { { 'Status' => 3, 'RemoteEnable' => [15, 0, 0] } }
  let(:fake) do
    served = { 'State' => JSON.generate(state), 'DOP2/1/1574?idx1=0&idx2=1' => program_context,
               'DOP2/1/1585' => device_context }
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: } then [200, {}, served.fetch(path.delete_prefix("/Devices/#{fab}/"))]
      else [204, {}, '']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def program_context
    start_at = { 2 => dop2_field(:u64, 1_700_000_000) }
    dop2_leaf(1, 1574, { 4 => dop2_field(:struct, { 13 => dop2_field(:struct, start_at) }),
                         7 => dop2_field(:struct, { 28 => dop2_field(:e16, 13) }) }, idx2: 1)
  end

  def device_prog_id = 13

  def device_context = dop2_leaf(1, 1585, { 7 => dop2_field(:struct, { 28 => dop2_field(:e16, device_prog_id) }) })

  def written = fake.requests.select { it.verb == 'PUT' }.map { [it.path, it.body.unpack1('H*')] }

  def parameter(id, type, value)
    dop2_leaf(2, 1577, { 1 => dop2_field(:e16, 13), 3 => dop2_field(:e8, 2), 2 => dop2_field(:u16, id),
                         7 => dop2_field(:struct, { id => dop2_field(type, value) }) }).unpack1('H*')
  end

  it 'sets the target temperature as the app does' do
    oven.target_temperature = 180
    expect(written).to eq([["/Devices/#{fab}/DOP2/2/1577",
                            '002200020629000000000004000107000d00030402000205000600071000010006054650']])
  end

  it 'selects a program with selection type 0' do
    oven.select_program(13)
    expect(written.map(&:last)).to eq(['001300020629000000000002000107000d00030400'])
  end

  it 'writes each parameter under the id and wire type the app gives it' do
    parameters = { core_target_temperature: 60, moisture: 3, microwave_power: 4, browning: 2, doneness: 1,
                   steam_bursts: 2, steam_burst_times: [60, 120], end_at: Time.at(1_700_003_600) }
    parameters.each { |name, value| oven.public_send(:"#{name}=", value) }
    expect(written.map(&:last)).to eq([parameter(7, :u16, 6000), parameter(2, :u8, 3), parameter(15, :u8, 4),
                                       parameter(30, :u8, 2), parameter(31, :u8, 1), parameter(18, :u8, 2),
                                       parameter(8, :u16, 60), parameter(9, :u16, 120),
                                       parameter(14, :u64, 1_700_003_600)])
  end

  it 'sends start at now as all ones' do
    oven.start_at = :now
    expect(written.map(&:last)).to eq([parameter(13, :u64, 0xFFFF_FFFF_FFFF_FFFF)])
  end

  it 'sets a duration alone, keeping the start time' do
    oven.duration = 1800
    expect(written.map(&:last)).to eq([parameter(12, :u32, 1800)])
  end

  it 'moves the start to its minimum before a zero duration, as the app does' do
    oven.duration = 0
    expect(written.map(&:last)).to eq([parameter(13, :u64, 1_700_000_000), parameter(12, :u32, 0)])
  end

  it 'refuses more than three steam burst times', :aggregate_failures do
    expect { oven.steam_burst_times = [60, 120, 180, 240] }.to raise_error(ArgumentError)
    expect(written).to be_empty
  end

  it 'sets the options one by one, keep warm last' do
    oven.set_options(keep_warm: true, rapid_heating: false)
    expect(written.map(&:last)).to eq([parameter(21, :bool, false), parameter(27, :bool, true)])
  end

  context 'without remote control' do
    let(:state) { { 'Status' => 3, 'RemoteEnable' => [0, 0, 0] } }

    it 'refuses a parameter without remote control', :aggregate_failures do
      expect { oven.target_temperature = 180 }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect(written).to be_empty
    end
  end

  context 'with mobile start while the oven runs' do
    let(:state) { { 'Status' => 5, 'RemoteEnable' => [15, 0, 1] } }

    it 'lets a mobile start change a parameter while the oven runs' do
      oven.grill_level = 2
      expect(written.map(&:last)).to eq([parameter(1, :u8, 2)])
    end
  end

  context 'without mobile start while the oven runs' do
    let(:state) { { 'Status' => 5, 'RemoteEnable' => [15, 0, 0] } }

    it 'refuses a parameter while the oven runs without mobile start', :aggregate_failures do
      expect { oven.grill_level = 2 }.to raise_error(Miele::Sdk::ActionUnavailableError, /mobile start/)
      expect(written).to be_empty
    end
  end

  context 'with mobile start but no remote control' do
    let(:state) { { 'Status' => 5, 'RemoteEnable' => [0, 0, 1] } }

    it 'refuses a parameter without remote control, mobile start or not' do
      expect { oven.grill_level = 2 }.to raise_error(Miele::Sdk::ActionUnavailableError, /remote control/)
    end
  end

  context 'with no program on the oven' do
    def device_prog_id = 0

    it 'refuses a parameter when the oven shows ProgId 0' do
      expect { oven.target_temperature = 180 }.to raise_error(Miele::Sdk::ActionUnavailableError, /program/)
    end
  end

  context 'with a Dop1 oven' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 12, 'ProtocolVersion' => 2) }

    it 'refuses an oven that speaks Dop1' do
      expect { oven.select_program(13) }.to raise_error(Miele::Sdk::ActionUnavailableError, /Dop1/)
    end
  end

  context 'when the oven serves no DOP2 locally' do
    let(:fake) do
      served = { 'State' => JSON.generate(state) }
      FakeAppliance.start do |request|
        case request
        in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
        in { path: /DOP2/ } then [404, {}, '']
        in { verb: 'GET', path: } then [200, {}, served.fetch(path.delete_prefix("/Devices/#{fab}/"))]
        end
      end
    end
    let(:cloud) do
      leaves = { '1/1574?idx1=0&idx2=1' => program_context, '1/1585' => device_context }
      FakeCloud.start do |request|
        next unless request.path.include?('/DOP2/')

        request.verb == 'GET' ? [200, {}, leaves.fetch(request.path.split('/DOP2/').last)] : [204, {}, '']
      end
    end

    before do
      Miele::Sdk.configure do |config|
        config.country = 'FR'
        config.email = 'koti@example.com'
        config.password = 'secret'
        config.locales_host = cloud.url
      end
    end

    after { cloud.stop }

    it 'writes through the cloud when the oven serves no DOP2 locally' do
      oven.target_temperature = 180
      device = "/V2/Devices/#{fab}/DOP2"
      expect(cloud.requests.map { [it.verb, it.path] }.last(2))
        .to eq([['GET', "#{device}/1/1574?idx1=0&idx2=1"], ['PUT', "#{device}/2/1577"]])
    end
  end
end
