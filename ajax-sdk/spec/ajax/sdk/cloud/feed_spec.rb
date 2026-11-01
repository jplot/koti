# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Feed do
  let(:client) { Ajax::Sdk::Cloud::Client.new(settings) }
  let(:settings) do
    instance_double(Ajax::Sdk::Configuration::Settings, grpc_host: 'local', grpc_port: 0, read_timeout: 2,
                                                        ca_file: nil, read_only: true, session_token: 'tok',
                                                        user_id: 'uid')
  end
  let(:script) { { space => [], summary => [], devices => [], notes => [], find => Array.new(5) { { success: {} } } } }
  let(:gateway) { FakeGateway.start(script) }

  before do
    allow(GRPC::ClientStub).to receive(:new).and_wrap_original do |original, *, **options|
      original.call("127.0.0.1:#{gateway.port}", :this_channel_is_insecure, **options)
    end
    allow(client.session).to receive_messages(ensure_login: nil, login: nil, metadata: {})
  end

  after { gateway.stop }

  def space = '/systems.ajax.api.mobile.v2.space.SpaceService/stream'

  def summary = '/systems.ajax.api.mobile.v2.space.SpaceService/streamUserSpaces'

  def devices
    '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service.stream_light_devices.StreamLightDevicesService/execute'
  end

  def notes = '/systems.ajax.api.mobile.v2.notification.NotificationLogService/streamUpdates'

  def find = '/systems.ajax.api.mobile.v2.notification.NotificationLogService/findNotifications'

  def events(tracker = nil, &) = client.events('space-1', **{ tracker: }.compact, &)

  def tracker = @tracker ||= Ajax::Sdk::Cloud::Tracker.new('space-1')

  def door(charge)
    profile = { id: '0000BEEF', statuses: [{ battery: { charge_level_percentage: charge } }] }
    { hub_device: { common_device: { hub_id: '0000ABCD', object_type: { door_protect: {} }, profile: } } }
  end

  def snapshot(charge) = { success: { snapshot: { light_device_items: [door(charge)] } } }

  def battery(charge)
    status = { status: { battery: { charge_level_percentage: charge } }, update_type: :UPDATE_TYPE_UPDATE }
    device_id = { hub_light_device_id: { hub_id: '0000ABCD', device_id: '0000BEEF' } }
    { success: { updates: { updates: [{ device_id:, status_update: status }] } } }
  end

  def note(number) = { id: "n#{number}", universal_token: "u#{number}", server_timestamp: { seconds: number } }

  def log(*numbers) = { success: { events: numbers.map { { notification_created: note(it) } } } }

  def requests = gateway.requests

  def await_streams
    sleep(0.01) until ([space, summary, devices, notes] - requests.map(&:first)).empty?
  end

  it 'ends when a stream ends, reopening nothing' do
    script[devices] = [[snapshot(100)]]

    expect(events.to_a.select { it.kind == :device }.map { it.after.battery.charge }).to eq([100])
  end

  it 'raises what breaks a stream, reopening nothing', :aggregate_failures do
    script[devices] = [[GRPC::Unavailable.new('down')]]

    expect { events.to_a }.to raise_error(GRPC::Unavailable)
    expect(requests.count { it.first == devices }).to eq(1)
  end

  it 'reports only what changed meanwhile when reopened with the same tracker' do
    script[devices] = [[snapshot(100)], [snapshot(50)]]
    events(tracker).to_a
    change = events(tracker).find { it.kind == :device }

    expect([change.before.battery.charge, change.after.battery.charge]).to eq([100, 50])
  end

  it 'reads back the notifications created meanwhile when reopened with the same tracker', :aggregate_failures do
    script[notes] = [[log(1), log(2)]]
    script[find] = [{ success: {} }, { success: { notifications: [note(3)] } }]
    events(tracker).to_a

    expect(events(tracker).find { it.kind == :notification }.key).to eq('n3')
    expect(requests).to include([find, hash_including(pagination: { backward_pagination_token: 'u2' })])
  end

  it 'reads them back across pages, in the order they happened', :aggregate_failures do
    script[notes] = [[log(1)]]
    page = { success: { notifications: (21..40).map { note(it) }.reverse } }
    script[find] = [{ success: {} }, page, { success: { notifications: [note(41)] } }]
    events(tracker).to_a

    expect(events(tracker).select { it.kind == :notification }.first(21).map(&:key)).to eq((21..41).map { "n#{it}" })
    expect(requests).to include([find, hash_including(pagination: { backward_pagination_token: 'u40' })])
  end

  it 'keeps for the next feed the notifications it never yielded' do
    script[notes] = [[log(1), log(2), :open], []]
    script[find] = [{ success: {} }, { success: { notifications: [note(2)] } }]
    events(tracker) do
      sleep(0.3)
      break
    end
    events(tracker).to_a

    expect(requests).to include([find, hash_including(pagination: { backward_pagination_token: 'u1' })])
  end

  it 'reads back on reopening a tracker whose space had no notification' do
    script[notes] = [[], []]
    script[find] = [{ success: {} }, { success: { notifications: [note(1)] } }]
    events(tracker).to_a

    expect(events(tracker).to_a.map(&:key)).to eq(['n1'])
  end

  it 'starts each walk of its enumerator afresh without a tracker' do
    script[devices] = [[snapshot(100)], [snapshot(100)]]
    feed = events

    expect([feed.to_a, feed.to_a].map { it.count { it.kind == :device } }).to eq([1, 1])
  end

  it 'raises a failed read-back' do
    script[notes] = [[log(1)]]
    script[find] = [{ success: {} }, GRPC::Unavailable.new('down')]
    events(tracker).to_a

    expect { events(tracker).to_a }.to raise_error(GRPC::Unavailable)
  end

  it 'delivers every change when the four streams talk at once', :aggregate_failures do
    script[devices] = [[snapshot(100), *(1..50).map { battery(it) }, :open]]
    script[notes] = [[*(1..50).map { log(it) }, :open]]
    collected = events.first(101)

    expect(collected.map(&:kind).tally).to eq({ device: 51, notification: 50 })
    expect(collected.select { it.kind == :device }.last.after.battery.charge).to eq(50)
  end

  it 'closes the four calls when the block raises', :aggregate_failures do
    script[devices] = [[snapshot(100), :open]]

    expect { events { await_streams || raise('boom') } }.to raise_error(RuntimeError, 'boom')
    expect(Array.new(4) { gateway.closed.pop(timeout: 5) }).to contain_exactly(space, summary, devices, notes)
    expect(requests.map(&:first).tally).to eq({ space => 1, summary => 1, devices => 1, notes => 1, find => 1 })
  end

  it 'raises a refused stream instead of retrying', :aggregate_failures do
    script[space] = [[{ failure: { permission_denied: {} } }]]

    expect { events.first }.to raise_error(Ajax::Sdk::Cloud::ReadError) { expect(it.reason).to eq(:permission_denied) }
    expect(requests.count { it.first == space }).to eq(1)
  end

  it 'stops when the enumerator is left early' do
    script[devices] = [[snapshot(100), :open]]
    events.map { await_streams || it }.first(1)

    expect(Array.new(4) { gateway.closed.pop(timeout: 5) }).to contain_exactly(space, summary, devices, notes)
  end
end
