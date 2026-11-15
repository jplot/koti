# frozen_string_literal: true

RSpec.describe Miele::Sdk::Hood do
  subject(:hood) { described_class.new('127.0.0.1', ident:, sleeper: ->(seconds) { naps << seconds }) }

  let(:fab) { '000123456789' }
  let(:naps) { [] }
  let(:protocol) { 4 }
  let(:extended) { { 30 => 0b1000, 34 => [0x05, 0x01], 37 => [0x20, 0x00] } }
  let(:fake) do
    served = { 'State' => JSON.generate('Status' => 4, 'Light' => 1, 'ExtendedState' => hex(extended)),
               'DOP2/2/1583?idx1=0&idx2=1' => dop2_leaf(2, 1583, { 1 => dop2_field(:e16, 0) }, idx2: 1),
               'DOP2/2/105?idx1=9001&idx2=1' => sf_value(9001, 0), 'DOP2/2/105?idx1=9007&idx2=1' => sf_value(9007, 0),
               'DOP2/2/105?idx1=9009&idx2=1' => sf_value(9009, 0) }
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: } then [200, {}, served.fetch(path.delete_prefix("/Devices/#{fab}/"))]
      else [200, {}, '{}']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  # GlobalPsSelectBaseAction.DefaultBytes, as the app's IL holds it (Hoods Implementation 45613-45620).
  def default_select
    '007800020629000100010001000a100015000105ffff000205ffff000305ffff000405ffff000505ffff000605ffff' \
      '000705ffff000805ffff000905ffff000a05ffff000b05ffff000c05ffff000d05ffff000e05ffff000f05ffff' \
      '001005ffff001105ffff001205ffff001305ffff001405ffff001505ffff'
  end

  def ident = Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 18, 'ProtocolVersion' => protocol)

  def hex(bytes, size = 73)
    data = Array.new(size, 0)
    bytes.each { |index, value| Array(value).each_with_index { |byte, offset| data[index + offset] = byte } }
    data.pack('C*').unpack1('H*')
  end

  def sf_value(id, value)
    dop2_leaf(2, 105, { 1 => dop2_field(:e16, id), 4 => dop2_field(:i16, value) }, idx1: id, idx2: 1)
  end

  def written
    fake.requests.reject { it.verb == 'GET' }.map do |request|
      body = request.path.include?('/DOP2/') ? request.body.unpack1('H*') : JSON.parse(request.body)
      [request.verb, request.path.delete_prefix("/Devices/#{fab}/"), body]
    end
  end

  # ModifyDop2Message sends the index read at as the header's attribute, and as both indexes of an instance read
  # above 0 (Hoods Implementation 19756-19790).
  def user_request(id) = ['PUT', 'DOP2/2/1583?idx1=0&idx2=1', format('000f00020000000000010001000107%04x', id)]

  def setting(id, value)
    body = format('00140002%<id>04x%<id>04x%<id>04x0002000107%<id>04x000406%<value>04x', id:, value:)
    ['PUT', "DOP2/2/105?idx1=#{id}&idx2=1", body]
  end

  it "sets the fan level of a DOP2 hood on the app's default message" do
    hood.fan_level = 2
    expect(written).to eq([['PUT', 'DOP2/2/1577', default_select.sub('000105ffff', '0001050002')]])
  end

  it 'sets the run-on of a DOP2 hood on the same message, a time the picker does not offer too',
     :aggregate_failures do
    expect(hood.fan_run_on_times).to eq([0, 5, 15])
    hood.fan_run_on_time = 15
    hood.fan_run_on_time = 10
    expect(written.map(&:last)).to eq([default_select.sub('000205ffff', '000205000f'),
                                       default_select.sub('000205ffff', '000205000a')])
  end

  it 'switches the lights of a DOP2 hood and resets its filters with user requests written back at 0/1' do
    hood.main_light = true
    hood.ambient_light = false
    hood.reset_grease_filter
    hood.reset_charcoal_filter
    expect(written).to eq([13, 20_002, 20_009, 20_008].map { user_request(it) })
  end

  it 'writes the settings of a DOP2 hood back on 2/105 at their SF id', :aggregate_failures do
    expect(hood.fragrance_supported?).to be(true)
    hood.ambient_light_while_cooking = true
    hood.auto_refresh = true
    hood.fragrance(:miele_program)
    expect(written).to eq([setting(9001, 1), setting(9007, 1), setting(9009, 2)])
  end

  it "refuses an action the hood's protocol has not", :aggregate_failures do
    [-> { hood.dehumidification = :off }, -> { hood.grease_melting = true },
     -> { hood.configure_ambient_light(mode: :ambient, rgb: [0, 0, 0], brightness: 0, colour_temperature: 0) }]
      .each { expect(&it).to raise_error(Miele::Sdk::ActionUnavailableError) }
    expect(written).to be_empty
  end

  context 'when waking a DOP2 hood' do
    let(:fake) do
      answers = states
      woken = wake_answer
      FakeAppliance.start do |request|
        case request
        in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
        in { verb: 'GET' } then [200, {}, JSON.generate(answers.size > 1 ? answers.shift : answers.first)]
        else woken
        end
      end
    end

    def states = [{ 'StandbyState' => 2 }, { 'SyncState' => 1, 'StandbyState' => 1 }, { 'StandbyState' => 1 }]

    def wake_answer = [200, {}, '{}']

    def exchanged = fake.requests.drop(1).map { [it.verb, (JSON.parse(it.body) unless it.body.empty?)] }

    it 'sends DeviceAction 2 once, then reads State every half second until it shows the hood awake',
       :aggregate_failures do
      hood.wake
      expect(exchanged).to eq([['GET', nil], ['PUT', { 'DeviceAction' => 2 }], ['GET', nil], ['GET', nil]])
      expect(naps).to eq([0.5, 0.5])
    end

    context 'when State shows it awake' do
      def states = [{ 'SyncState' => 2, 'StandbyState' => 1 }]

      it 'sends nothing, as the app finds it already awake' do
        hood.wake
        expect(exchanged).to eq([['GET', nil]])
      end
    end

    context 'when State shows it synchronized without a StandbyState' do
      def states = [{ 'SyncState' => 2 }, { 'SyncState' => 2, 'StandbyState' => 1 }]

      it 'takes it as asleep and wakes it, as the app reads no StandbyState as 0', :aggregate_failures do
        hood.wake
        expect(exchanged).to eq([['GET', nil], ['PUT', { 'DeviceAction' => 2 }], ['GET', nil]])
      end
    end

    context 'when State never shows it awake' do
      def states = [{ 'StandbyState' => 2 }]

      it 'raises ActionFailedError after a minute of reads, as the app gives up', :aggregate_failures do
        expect { hood.wake }.to raise_error(Miele::Sdk::ActionFailedError)
        expect(exchanged.tally).to eq(['GET', nil] => 120, ['PUT', { 'DeviceAction' => 2 }] => 1)
        expect(naps).to eq([0.5] * 120)
      end
    end

    context 'when the hood refuses DeviceAction 2' do
      def wake_answer = [400, {}, '']

      it 'raises the refusal without reading State again, which the app reports as a failed wake',
         :aggregate_failures do
        expect { hood.wake }.to raise_error(Miele::Sdk::ResponseError, 'appliance answered 400')
        expect(exchanged).to eq([['GET', nil], ['PUT', { 'DeviceAction' => 2 }]])
      end
    end
  end

  context 'with an Opcode hood' do
    let(:protocol) { 1 }
    let(:extended) { { 25 => 0b1000 } }

    def hex(bytes, size = 32) = super

    def oc85 = written.map { it.last['Request'] if it[1] == 'Oc85/' }

    it 'sets the run-on time of an Opcode hood through Oc85, in one byte', :aggregate_failures do
      hood.fan_run_on_time = 15
      expect { hood.fan_run_on_time = 256 }.to raise_error(ArgumentError)
      expect(written).to eq([['POST', 'Oc85/', { 'Request' => '100006090F00000000' }]])
    end

    it 'sends the fan level of an Opcode hood twice, half a second apart, as the app does', :aggregate_failures do
      hood.fan_level = 4
      expect(oc85).to eq(%w[100006080104000000 100006080104000000])
      expect(naps).to eq([0.5])
    end

    it 'switches its light through State with a string, and resets its filters through Oc85' do
      hood.main_light = true
      hood.main_light = false
      hood.reset_grease_filter
      hood.reset_charcoal_filter
      expect(written).to eq([['PUT', 'State/', { 'Light' => '1' }], ['PUT', 'State/', { 'Light' => '2' }],
                             ['POST', 'Oc85/', { 'Request' => '0B0003000300' }],
                             ['POST', 'Oc85/', { 'Request' => '0B0003000400' }]])
    end

    it 'refuses the ambient light and the fragrance, which Opcode has no request for', :aggregate_failures do
      expect { hood.ambient_light = true }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect { hood.fragrance(:start) }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect(hood.fragrance_supported?).to be(false)
    end
  end

  context 'with a hood in protocol 3' do
    let(:protocol) { 3 }

    it 'drives its fan through Oc85 and resets its filters through DOP2, as the app picks them' do
      hood.fan_level = 1
      hood.reset_grease_filter
      expect(written).to eq([['POST', 'Oc85/', { 'Request' => '100006080101000000' }],
                             ['POST', 'Oc85/', { 'Request' => '100006080101000000' }], user_request(20_009)])
    end
  end

  context 'when the hood screen is pushed in' do
    let(:extended) { {} }

    it 'tells the app offers no fragrance without its function bit' do
      expect(hood.fragrance_supported?).to be(false)
    end

    it 'sets the fan, which the app refuses', :aggregate_failures do
      expect(hood.fan_settable?).to be(false)
      hood.fan_level = 2
      expect(written.map { it[1] }).to eq(['DOP2/2/1577'])
    end
  end
end
