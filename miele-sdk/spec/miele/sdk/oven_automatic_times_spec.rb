# frozen_string_literal: true

RSpec.describe Miele::Sdk::Oven do
  subject(:oven) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 13, 'ProtocolVersion' => 4) }
  let(:resources) { {} }
  let(:fake) do
    served = resources
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: } then [200, {}, served.fetch(path.delete_prefix("/Devices/#{fab}/"))]
      else [204, {}, '']
      end
    end
  end
  let(:kept) { times(Time.at(1_600_000_000), Time.at(1_600_003_600), prog_id: 14) }

  before { connect_to(fake) }

  after { fake.stop }

  def at = Time.at(1_700_007_200)

  def serve(type: 3, starts: 1_700_000_000, ends: 1_700_003_600, attributes: {}, parameters: {})
    shown = { 1 => dop2_field(:e16, 0), 10 => dop2_field(:e8, type), 28 => dop2_field(:e16, 13) }
    minimums = { 13 => shown_parameter(:u64, 0, min: starts), 14 => shown_parameter(:u64, 0, min: ends) }
    resources['DOP2/1/1574?idx1=0&idx2=1'] =
      dop2_leaf(1, 1574, { 4 => dop2_field(:struct, oven_parameters(minimums.merge(parameters))),
                           7 => dop2_field(:struct, shown.merge(attributes).compact) }, idx2: 1)
  end

  def times(start_at, end_at, prog_id: 13) = described_class::AutomaticTimes.new(prog_id:, start_at:, end_at:)

  def dop2_requests
    fake.requests.select { it.path.include?('/DOP2/') }.map { [it.verb, it.path.delete_prefix("/Devices/#{fab}/")] }
  end

  def written = fake.requests.select { it.verb == 'PUT' }.map { it.body.unpack1('H*') }

  def parameter(id, value)
    dop2_leaf(2, 1577, { 1 => dop2_field(:e16, 13), 3 => dop2_field(:e8, 2), 2 => dop2_field(:u16, id),
                         7 => dop2_field(:struct, { id => dop2_field(:u64, value) }) }).unpack1('H*')
  end

  it 'keeps the start of an automatic program and the end its minimums give, reading 1/1574 and writing nothing',
     :aggregate_failures do
    serve
    expect(oven.set_start_at(at, kept: nil)).to eq(times(at, at + 3_600))
    expect(dop2_requests).to eq([%w[GET DOP2/1/1574?idx1=0&idx2=1]])
  end

  it 'keeps the end of an automatic program and the start its minimums give, writing nothing', :aggregate_failures do
    serve
    expect(oven.set_end_at(at, kept: nil)).to eq(times(at - 3_600, at))
    expect(written).to be_empty
  end

  it 'keeps nothing for an automatic program to start now, writing nothing', :aggregate_failures do
    serve
    expect(oven.set_start_at(:now, kept:)).to be_nil
    expect(written).to be_empty
  end

  it 'raises for a start neither a Time nor :now on an automatic program, as on another', :aggregate_failures do
    [3, 5].each do |type|
      serve(type:)
      expect { oven.set_start_at(1_700_007_200, kept:) }.to raise_error(NoMatchingPatternError)
    end
    expect(written).to be_empty
  end

  it 'reads a minimum of 0 or all ones as year 1, as the app does', :aggregate_failures do
    year_one = Time.utc(1).to_i
    serve(starts: 0)
    expect(oven.set_start_at(at, kept: nil).end_at).to eq(at + (1_700_003_600 - year_one))
    serve(ends: 0xFFFF_FFFF_FFFF_FFFF)
    expect(oven.set_end_at(at, kept: nil).start_at).to eq(at - (year_one - 1_700_000_000))
  end

  it 'writes the times of an automatic program counting down its delayed start, keeping what was kept',
     :aggregate_failures do
    serve(attributes: { 1 => dop2_field(:e16, 28_002) })
    expect([oven.set_start_at(:now, kept:), oven.set_start_at(at, kept:), oven.set_end_at(at, kept:)]).to eq([kept] * 3)
    expect(written).to eq([parameter(13, 0xFFFF_FFFF_FFFF_FFFF), parameter(13, at.to_i), parameter(14, at.to_i)])
  end

  it 'writes the times of a program that is not automatic, without its phase', :aggregate_failures do
    serve(type: 5, attributes: { 1 => nil })
    expect([oven.set_start_at(at, kept:), oven.set_end_at(at, kept: nil)]).to eq([kept, nil])
    expect(written).to eq([parameter(13, at.to_i), parameter(14, at.to_i)])
  end

  it 'writes a start before 1970 wrapped into 64 bits, as the app does' do
    serve(type: 5)
    oven.set_start_at(Time.utc(1), kept: nil)
    expect(written).to eq([parameter(13, 0xFFFF_FFF1_886E_0900)])
  end

  it 'writes an end before 1970 wrapped into 64 bits, as the app does' do
    serve(type: 5)
    oven.set_end_at(Time.utc(1969, 12, 31), kept: nil)
    expect(written).to eq([parameter(14, 0xFFFF_FFFF_FFFE_AE80)])
  end

  it 'reads 1/1574 once before the write, as the app answers its second read from the same poll' do
    serve(type: 5)
    oven.set_start_at(at, kept: nil)
    expect(dop2_requests).to eq([%w[GET DOP2/1/1574?idx1=0&idx2=1], %w[PUT DOP2/2/1577]])
  end

  it "reads 1/1574 with the caller's token, then writes within the 15 s that begin after it" do
    Miele::Sdk.config.read_timeout = 30
    serve(type: 5)
    oven.fab
    timeouts = read_timeouts
    oven.set_start_at(at, kept: nil)
    expect(timeouts.map(&:round)).to eq([30, 15])
  end

  context 'when the read of 1/1574 takes 16 s' do
    subject(:oven) { described_class.new('127.0.0.1', ident:, clock: -> { fake.requests.size * 16.0 }) }

    it 'still writes the time' do
      serve(type: 5)
      oven.fab
      oven.set_end_at(at, kept: nil)
      expect(written).to eq([parameter(14, at.to_i)])
    end
  end

  it 'sends and keeps nothing without the program type the app reads first', :aggregate_failures do
    serve(attributes: { 10 => nil })
    expect { oven.set_start_at(at, kept: nil) }.to raise_error(Miele::Sdk::ActionUnavailableError, /program type/)
    expect { oven.set_end_at(at, kept: nil) }.to raise_error(Miele::Sdk::ActionUnavailableError, /program type/)
    expect(written).to be_empty
  end

  it 'sends and keeps nothing for an automatic program without the phase the app reads', :aggregate_failures do
    serve(attributes: { 1 => nil })
    expect { oven.set_start_at(:now, kept: nil) }.to raise_error(Miele::Sdk::ActionUnavailableError, /phase/)
    expect(written).to be_empty
  end

  it 'keeps nothing without the minimum end the app reads' do
    serve(parameters: { 14 => dop2_field(:struct, { 1 => dop2_field(:u8, 9), 4 => dop2_field(:u64, 0) }) })
    expect { oven.set_start_at(at, kept: nil) }.to raise_error(Miele::Sdk::ActionUnavailableError, /minimum/)
  end

  it 'has no setter for the times, whose return the client could not read' do
    expect(%i[start_at= end_at=].select { oven.respond_to?(it) }).to be_empty
  end

  def device(type: 3, prog_id: 13)
    shown = { 10 => dop2_field(:e8, type), 28 => dop2_field(:e16, prog_id) }
    Miele::Sdk::Objects::Oven::GlobalDeviceContext.from({ 7 => dop2_field(:struct, shown) })
  end

  it 'tells the app shows the kept times while 1/1585 shows their automatic program, sending nothing',
     :aggregate_failures do
    shown = times(at, at + 3_600)
    expect(oven.kept_times_shown?(shown, device)).to be(true)
    expect([oven.kept_times_shown?(shown, device(prog_id: 14)), oven.kept_times_shown?(shown, device(type: 5)),
            oven.kept_times_shown?(nil, device)]).to eq([false] * 3)
    expect(fake.requests).to be_empty
  end

  it 'tells the app shows no times while 1/1585 shows ProgId 0, kept for it though they are' do
    expect(oven.kept_times_shown?(times(at, at, prog_id: 0), device(prog_id: 0))).to be(false)
  end
end
