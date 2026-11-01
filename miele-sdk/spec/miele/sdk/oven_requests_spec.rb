# frozen_string_literal: true

RSpec.describe Miele::Sdk::Oven do
  subject(:oven) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 13, 'ProtocolVersion' => 4) }
  let(:resources) { { 'State' => JSON.generate('Status' => 3, 'RemoteEnable' => [15, 0, 0]) } }
  let(:fake) do
    served = resources
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: } then [200, {}, served.fetch(path.delete_prefix("/Devices/#{fab}/"))]
      else served[:put]&.shift || [204, {}, '']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def written
    fake.requests.select { it.verb == 'PUT' }.map { [it.path.delete_prefix("/Devices/#{fab}/"), it.body.unpack1('H*')] }
  end

  def user_request(id) = dop2_leaf(2, 1583, { 1 => dop2_field(:e16, id) }).unpack1('H*')

  def parameter(id, type, value)
    dop2_leaf(2, 1577, { 1 => dop2_field(:e16, 13), 3 => dop2_field(:e8, 2), 2 => dop2_field(:u16, id),
                         7 => dop2_field(:struct, { id => dop2_field(type, value) }) }).unpack1('H*')
  end

  def value(type, mask, current, min: 0, max: 0)
    dop2_field(:struct, { 1 => dop2_field(:u8, mask), 2 => dop2_field(type, min), 3 => dop2_field(type, max),
                          4 => dop2_field(type, current) })
  end

  def state(status, remote = 15, program_id: 13)
    resources['State'] = JSON.generate('Status' => status, 'RemoteEnable' => [remote, 0, 0], 'ProgramID' => program_id)
  end

  def attributes(type: 1, phase: 0, prog_id: 13, continue_cooking: 0)
    { 1 => dop2_field(:e16, phase), 10 => dop2_field(:e8, type), 16 => dop2_field(:e8, continue_cooking),
      28 => dop2_field(:e16, prog_id) }
  end

  def burst_attributes(type: 2, remaining: 1, bit_field: 0)
    remaining = { 1 => dop2_field(:u8, 8), 2 => dop2_field(:u8, remaining) }
    attributes(type:).merge(12 => dop2_field(:struct, remaining), 19 => dop2_field(:u32, bit_field))
  end

  def serve_burst(count: 1, mask: 9, selected: 13, times: [8, 9, 10], **shown)
    parameters = times.to_h { [it, value(:u16, 9, 0)] }.merge(18 => value(:u8, mask, count))
    serve_burst_device(burst_attributes(**shown))
    resources['DOP2/1/1574?idx1=0&idx2=1'] =
      dop2_leaf(1, 1574, { 4 => dop2_field(:struct, parameters),
                           7 => dop2_field(:struct, attributes(type: 2, prog_id: selected)) }, idx2: 1)
  end

  def serve_burst_device(shown)
    resources['DOP2/1/1585'] = dop2_leaf(1, 1585, { 7 => dop2_field(:struct, shown),
                                                    9 => dop2_field(:e16_array, [59]) })
  end

  def serve(requests, parameters: {}, **shown)
    attributes = attributes(**shown)
    resources['DOP2/1/1585'] = dop2_leaf(1, 1585, { 7 => dop2_field(:struct, attributes),
                                                    9 => dop2_field(:e16_array, requests) })
    resources['DOP2/1/1574?idx1=0&idx2=1'] =
      dop2_leaf(1, 1574, { 4 => dop2_field(:struct, oven_parameters(parameters)),
                           7 => dop2_field(:struct, attributes) }, idx2: 1)
  end

  it 'starts with request 1 on unit 2' do
    serve([1, 2])
    oven.start
    expect(written).to eq([['DOP2/2/1583', '000f0002062f0000000000010001070001']])
  end

  it 'starts with 113 when 1 is not offered' do
    serve([2, 113])
    oven.start
    expect(written.map(&:last)).to eq([user_request(113)])
  end

  it 'refuses a start time for a program that is not automatic', :aggregate_failures do
    serve([1])
    expect { oven.start(at: Time.at(1_700_000_000)) }.to raise_error(ArgumentError)
    expect(written).to be_empty
  end

  it 'starts an automatic program by writing its start time, now unless given' do
    serve([1], type: 3)
    oven.start
    oven.start(at: Time.at(1_700_000_000))
    expect(written.map(&:last)).to eq([parameter(13, :u64, 0xFFFF_FFFF_FFFF_FFFF), parameter(13, :u64, 1_700_000_000)])
  end

  it 'writes the required parameters not yet confirmed before starting' do
    serve([1], parameters: { 6 => value(:u16, 2, 18_000), 7 => value(:u16, 6, 6_000),
                             12 => value(:u32, 2, 1_800, min: 60, max: 3_600), 30 => value(:u8, 0, 2) })
    oven.start
    expect(written.map(&:last)).to eq([parameter(6, :u16, 18_000), parameter(12, :u32, 1_800), user_request(1)])
  end

  it 'writes a required temperature through degrees and back, truncated as the app does' do
    serve([1], parameters: { 6 => value(:u16, 2, 3_730), 7 => value(:u16, 2, 230) })
    oven.start
    expect(written.map(&:last)).to eq([parameter(6, :u16, 3_729), parameter(7, :u16, 229), user_request(1)])
  end

  it 'writes every required parameter, then raises the first refusal without starting', :aggregate_failures do
    serve([1], parameters: { 6 => value(:u16, 2, 18_000), 7 => value(:u16, 2, 6_000) })
    resources[:put] = [[500, {}, '']]
    expect { oven.start }.to raise_error(Miele::Sdk::ResponseError, 'appliance answered 500')
    expect(written.map(&:last)).to eq([parameter(6, :u16, 18_000), parameter(7, :u16, 6_000)])
  end

  it 'writes no required parameter and does not start while 1/1574 lacks one of the eight', :aggregate_failures do
    serve([1], parameters: { 6 => value(:u16, 2, 18_000), 31 => nil })
    expect { oven.start }.to raise_error(Miele::Sdk::ActionUnavailableError, /parameter/)
    expect(written).to be_empty
  end

  it 'refuses to start a program whose duration is required but not set', :aggregate_failures do
    serve([1], parameters: { 12 => value(:u32, 2, 0xFFFF_FFFF) })
    expect { oven.start }.to raise_error(Miele::Sdk::ActionUnavailableError, /duration/)
    expect(written).to be_empty
  end

  it 'stops a running program with the first close request it offers' do
    state(5)
    serve([2, 56, 57])
    oven.stop
    expect(written.map(&:last)).to eq([user_request(56)])
  end

  it 'stops with request 2 a program that could still start' do
    state(4)
    serve([1, 2, 55])
    oven.stop
    expect(written.map(&:last)).to eq([user_request(2)])
  end

  it 'takes a pause the oven asks about for a started program, a plain pause for a selected one' do
    state(6)
    serve([2, 55], phase: 10_003)
    oven.stop
    serve([2, 55])
    oven.stop
    expect(written.map(&:last)).to eq([user_request(55), user_request(2)])
  end

  it 'takes an oven on, held by a query during a cooking function, for a paused program' do
    state(2)
    serve([2, 55], type: 2, phase: 10_003)
    oven.stop
    serve([2, 55], type: 0, phase: 10_003)
    oven.stop
    expect(written.map(&:last)).to eq([user_request(55), user_request(2)])
  end

  it 'stops a paused sous-vide program showing info 198 with request 2' do
    state(6, program_id: 72)
    serve([2, 55], phase: 10_001)
    resources['DOP2/1/131?idx1=0&idx2=1'] =
      dop2_leaf(1, 131, { 1 => dop2_field(:struct_array, [{ 1 => dop2_field(:e16, 198) }]) }, idx2: 1)
    oven.stop
    expect(written.map(&:last)).to eq([user_request(2)])
  end

  it 'refuses a stop the oven does not offer, or during a pyrolysis abort', :aggregate_failures do
    state(5)
    serve([1])
    expect { oven.stop }.to raise_error(Miele::Sdk::ActionUnavailableError)
    serve([2, 55], prog_id: 324)
    expect { oven.stop }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect(written).to be_empty
  end

  it 'refuses to stop under local control', :aggregate_failures do
    state(5, 7)
    serve([2, 55])
    expect { oven.stop }.to raise_error(Miele::Sdk::ActionUnavailableError, /remote control/)
    expect(written).to be_empty
  end

  it 'sends the end of keeping warm while 1/131 shows message 20' do
    serve([59])
    resources['DOP2/1/131?idx1=0&idx2=1'] =
      dop2_leaf(1, 131, { 2 => dop2_field(:struct_array, [{ 1 => dop2_field(:e16, 20) }]) }, idx2: 1)
    oven.stop_keeping_warm
    expect(written.map(&:last)).to eq([user_request(68)])
  end

  it 'refuses the requests the oven does not offer', :aggregate_failures do
    serve([1, 2])
    resources['DOP2/1/131?idx1=0&idx2=1'] = dop2_leaf(1, 131, {}, idx2: 1)
    %i[continue_cooking steam_burst stop_keeping_warm].each do |request|
      expect { oven.public_send(request) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
    expect(written).to be_empty
  end

  context 'with a manual steam burst in a running function' do
    before do
      state(5)
      serve_burst
    end

    it 'sends a steam burst on unit 2' do
      oven.steam_burst
      expect(written).to eq([['DOP2/2/1583', '000f0002062f000000000001000107003b']])
    end

    it 'sends the last steam burst while it is under way, BitField 16 as the app compares it' do
      serve_burst(remaining: 0, bit_field: 16)
      oven.steam_burst
      expect(written.map(&:last)).to eq([user_request(59)])
    end

    it 'refuses a burst the app shows no button for', :aggregate_failures do
      [{ count: 4 }, { mask: 1 }, { selected: 14 }, { remaining: 0 }, { type: 1 }].each do |change|
        serve_burst(**change)
        expect { oven.steam_burst }.to raise_error(Miele::Sdk::ActionUnavailableError, /steam burst/)
      end
      expect(written).to be_empty
    end

    it 'refuses a burst without a steam burst time on 1/1574 or a BitField on 1/1585', :aggregate_failures do
      serve_burst(times: [8, 9])
      expect { oven.steam_burst }.to raise_error(Miele::Sdk::ActionUnavailableError, /steam burst/)
      serve_burst
      serve_burst_device(burst_attributes.except(19))
      expect { oven.steam_burst }.to raise_error(Miele::Sdk::ActionUnavailableError, /steam burst/)
      expect(written).to be_empty
    end

    it 'refuses a burst to a programmed oven, or without a REST ProgramID', :aggregate_failures do
      state(3)
      expect { oven.steam_burst }.to raise_error(Miele::Sdk::ActionUnavailableError, /steam burst/)
      state(5, program_id: 0)
      expect { oven.steam_burst }.to raise_error(Miele::Sdk::ActionUnavailableError, /steam burst/)
      expect(written).to be_empty
    end
  end

  context 'with a Dop1 oven' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 12, 'ProtocolVersion' => 2) }

    it 'stops a Dop1 oven through State' do
      resources['State'] = JSON.generate('Status' => 5, 'ProgramID' => 13, 'ProgramType' => 0)
      oven.stop
      request = fake.requests.last
      expect([request.verb, request.path, JSON.parse(request.body)])
        .to eq(['PUT', "/Devices/#{fab}/State", { 'ProcessAction' => 2 }])
    end

    it 'refuses to stop a Dop1 oven running no program, or a cleaning', :aggregate_failures do
      resources['State'] = JSON.generate('Status' => 2, 'ProgramID' => 0, 'ProgramType' => 0)
      expect { oven.stop }.to raise_error(Miele::Sdk::ActionUnavailableError)
      resources['State'] = JSON.generate('Status' => 5, 'ProgramID' => 13, 'ProgramType' => 3)
      expect { oven.stop }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect(written).to be_empty
    end

    it 'refuses to start a Dop1 oven' do
      expect { oven.start }.to raise_error(Miele::Sdk::ActionUnavailableError, /Dop1/)
    end
  end
end
