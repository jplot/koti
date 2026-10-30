# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Feed do
  let(:client) { Ajax::Sdk::Cloud::Client.new(settings) }
  let(:settings) do
    instance_double(Ajax::Sdk::Configuration::Settings, grpc_host: 'local', grpc_port: 0, read_timeout: 2,
                                                        ca_file: nil, read_only: true, session_token: 'tok',
                                                        user_id: 'uid')
  end
  let(:slept) { Queue.new }
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

  def events(&) = client.events('space-1', sleeper: ->(seconds) { slept << seconds }, &)

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

  it 'emits what changed while the devices stream was down', :aggregate_failures do
    script[devices] = [[snapshot(100), GRPC::Unavailable.new('down')], [snapshot(50), :open]]
    change = events.find { it.kind == :device && it.before }

    expect([change.before.battery.charge, change.after.battery.charge]).to eq([100, 50])
    expect(slept.pop(timeout: 1)).to eq(1)
  end

  it 'fills the notification gap after a reconnect', :aggregate_failures do
    script[notes] = [[log(1), GRPC::Unavailable.new('down')]]
    script[find] = [{ success: {} }, { success: { notifications: [note(2)] } }]

    expect(events.find { it.kind == :notification && it.key == 'n2' }.after.token).to eq('u2')
    expect(requests).to include([find, hash_including(pagination: { backward_pagination_token: 'u1' })])
  end

  it 'keeps following when the catch-up fails during an outage' do
    script[notes] = [[log(1), GRPC::Unavailable.new('down')], [GRPC::Unavailable.new('still down')]]
    script[find] = [{ success: {} }, GRPC::Unavailable.new('down'), { success: { notifications: [note(2)] } }]

    expect(events.find { it.kind == :notification && it.key == 'n2' }).not_to be_nil
  end

  it 'reads back the notifications of a first outage', :aggregate_failures do
    script[notes] = [[GRPC::Unavailable.new('down')]]
    script[find] = [{ success: { notifications: [note(1)] } }, { success: { notifications: [note(5)] } }]

    expect(events.find { it.kind == :notification }.key).to eq('n5')
    expect(requests).to include([find, hash_including(pagination: { backward_pagination_token: 'u1' })])
  end

  it 'catches up across pages, in the order they happened', :aggregate_failures do
    script[notes] = [[log(1), GRPC::Unavailable.new('down')]]
    page = { success: { notifications: (21..40).map { note(it) }.reverse } }
    script[find] = [{ success: {} }, page, { success: { notifications: [note(41)] } }]

    expect(events.select { it.kind == :notification }.first(22).map(&:key)).to eq(['n1', *(21..41).map { "n#{it}" }])
    expect(requests).to include([find, hash_including(pagination: { backward_pagination_token: 'u40' })])
  end

  it 'waits 1, 2, 4, 8, 16 then 30 s between attempts, and 1 s again after a message' do
    down = GRPC::Unavailable.new('down')
    script[devices] = [*Array.new(7) { [down] }, [snapshot(100), down], [snapshot(50), :open]]
    events.find { it.kind == :device && it.before }

    expect(Array.new(8) { slept.pop(timeout: 1) }).to eq([1, 2, 4, 8, 16, 30, 30, 1])
  end

  it 'reopens after every retriable error' do
    errors = [GRPC::DeadlineExceeded, GRPC::Internal, GRPC::Cancelled, GRPC::Unknown, GRPC::ResourceExhausted]
    script[devices] = [*errors.map { [it.new('down')] }, [GRPC::Unauthenticated.new], [GRPC::Unauthenticated.new],
                       [snapshot(100), :open]]

    expect(events.find { it.kind == :device }.after.battery.charge).to eq(100)
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
