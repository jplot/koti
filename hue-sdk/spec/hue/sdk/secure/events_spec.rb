# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::Events do
  subject(:events) { home.events }

  include_context 'with the Hue cloud'

  let(:schema) { Hue::Sdk::Secure::Schema }
  let(:timeline) { '/data/timeline/security/home-1' }
  let(:owner) { { 'rid' => 'r-1', 'rtype' => 'device' } }

  def message(type, event)
    { 'id' => 'e-1', 'home_id' => 'home-1', 'timestamp' => 't', 'type' => type, 'event' => event }
  end

  def page_of(*messages, cursor: nil)
    answers.push(FakeCloud.json({ 'data' => messages }, 200, cursor ? { 'x-cursor' => cursor } : {}))
  end

  describe "a camera event's clip" do
    let(:camera) do
      { 'id' => 'ev-1', 'type' => 'update', 'resource_uri' => '/home/home-1/device/cam-1/service/camera/0' }
    end

    def read(type, event, metadata = nil)
      page_of(message(type, event).merge('metadata' => metadata))
      events.page(limit: 1).events.first
    end

    it 'gives the camera and the clip of a detection event' do
      event = read('camera', camera.merge('resource_type' => 'security_motion_eventing'),
                   'clip' => { 'clip_event_id' => 'clip-9' })
      expect([event.camera_id, event.clip_id]).to eq(%w[cam-1 clip-9])
    end

    it 'takes the camera event id as the clip of an upload event' do
      expect(read('camera', camera.merge('resource_type' => 'camera_video_clips_eventing')).clip_id).to eq('ev-1')
    end

    it 'names no clip for a camera event that has none', :aggregate_failures do
      expect(read('camera', camera.merge('resource_type' => 'device_power')).clip_id).to be_nil
      motion = camera.merge('resource_type' => 'security_motion_eventing')
      expect(read('camera', motion, 'clip' => 'malformed').clip_id).to be_nil
    end

    it 'gives no camera nor clip for another event' do
      event = read('geofence', { 'type' => 'security_empty', 'device_name' => 'phone' })
      expect([event.camera_id, event.clip_id]).to eq([nil, nil])
    end
  end

  it 'sends the cursor as a header and reads the next one', :aggregate_failures do
    page_of(cursor: 'next-1')
    read = events.page(limit: 20, cursor: 'first')
    expect(cloud.requests.last.headers['x-cursor']).to eq('first')
    expect(read.cursor).to eq('next-1')
  end

  it 'sends limit, start_time and end_time in UTC ISO 8601, without the security prefix' do
    page_of
    events.page(limit: 20, start_time: Time.new(2026, 11, 7, 22, 0, 0, '+01:00'),
                end_time: Time.new(2026, 11, 7, 23, 0, 0, '+01:00'))
    expect(cloud.requests.last.path).to eq("#{timeline}/range?limit=20&start_time=2026-11-07T21%3A00%3A00.000Z" \
                                           '&end_time=2026-11-07T22%3A00%3A00.000Z')
  end

  it 'leaves the times the caller gives as they were, a frozen one included' do
    page_of
    start_time = Time.new(2026, 11, 7, 22, 0, 0, '+01:00').freeze
    events.page(limit: 20, start_time:)
    expect(start_time.utc_offset).to eq(3600)
  end

  it 'sends the microseconds of a time as the app does, and milliseconds when they are all there is' do
    2.times { answer_empty }
    events.all_safe(device_timestamp: Time.utc(2026, 11, 7, 21, 0, 0, 123_456))
    events.all_safe(device_timestamp: Time.utc(2026, 11, 7, 21, 0, 0, 123_000))
    expect(cloud.requests.map { JSON.parse(it.body)['device_timestamp'] })
      .to eq(%w[2026-11-07T21:00:00.123456Z 2026-11-07T21:00:00.123Z])
  end

  it 'skips an item of data that is not an event, as the app does' do
    page_of(1, [], message('geofence', { 'type' => 'security_presence', 'device_name' => 'phone' }))
    expect(events.page(limit: 3).events.map(&:type)).to eq(['geofence'])
  end

  it 'gives no cursor on the last page' do
    page_of
    expect(events.page(limit: 20).cursor).to be_nil
  end

  {
    'action_all_safe' => [{ 'user_id' => 'u', 'user_display_name' => 'n', 'device_timestamp' => 't',
                            'received_timestamp' => 't' }, :ActionAllSafeEvent],
    'arm_state' => [{ 'arm_state' => 'armed_away', 'source' => { 'type' => 'user', 'id' => 'u' }, 'trigger_time' => 't',
                      'apply_time' => 't' }, :ArmEvent],
    'trigger' => [{ 'type' => 'alarm_started', 'device_timestamp' => 't', 'received_timestamp' => 't',
                    'source' => { 'type' => 'user', 'id' => 'u' } }, :TriggerEvent],
    'geofence' => [{ 'type' => 'security_empty', 'device_name' => 'phone' }, :GeofenceEvent],
    'clipv2' => [{ 'type' => 'contact', 'id' => 'c', 'owner' => { 'rid' => 'r', 'rtype' => 'device' } },
                 :ContactClipV2Event],
    'camera' => [{ 'resource_type' => 'doorbell_button_event', 'id' => 'c', 'type' => 'update' },
                 :DoorbellButtonCameraEvent],
    'management' => [{ 'type' => 'bridge_heartbeat', 'bridge_id' => 'b', 'state' => 'reachable' },
                     :BridgeConnectivityEvent],
    'timeline' => [{ 'type' => 'purge_timeline' }, :PurgeTimelineEvent]
  }.each do |type, (event, class_name)|
    it "reads a #{type} event as the app's #{class_name}" do
      page_of(message(type, event))
      expect(events.page(limit: 1).events.first.event).to be_a(schema.const_get(class_name))
    end
  end

  it 'chooses the class of a camera event by its resource_type' do
    page_of(message('camera', { 'resource_type' => 'wifi_connectivity', 'id' => 'c', 'type' => 'update',
                                'data' => { 'strength' => 3 } }))
    expect(events.page(limit: 1).events.first.event).to be_a(schema::WifiConnectivityCameraEvent)
  end

  it 'keeps a Hash for a type it does not know, or a shape it cannot read, and reads the rest of the page' do
    page_of(message('future', { 'x' => 1 }), message('clipv2', { 'type' => 'motion', 'owner' => 'r' }),
            message('geofence', { 'type' => 'security_presence', 'device_name' => 'phone' }))
    expect(events.page(limit: 3).events.map { it.event.class })
      .to eq([Hash, Hash, schema::GeofenceEvent])
  end

  it 'reads the first item of the significant event, nil when there is none', :aggregate_failures do
    page_of(message('timeline', { 'type' => 'refresh_timeline' }))
    page_of
    expect(events.last_significant.event).to be_a(schema::RefreshTimelineEvent)
    expect(events.last_significant).to be_nil
    expect(cloud.requests.last.path).to eq("#{timeline}/significant-event")
  end

  it 'sends the all-safe and the alarm trigger bodies, and expects no content', :aggregate_failures do
    2.times { answer_empty }
    events.all_safe(device_timestamp: Time.utc(2026, 11, 7, 21))
    all_safe = sent
    events.trigger_alarm('alarm_stopped', device_timestamp: Time.utc(2026, 11, 7, 21))
    expect(all_safe).to eq(['POST', '/data/resolve/all_safe', 'application/json',
                            '{"home_id":"home-1","device_timestamp":"2026-11-07T21:00:00.000Z"}'])
    expect(sent).to eq(['POST', '/data/triggers/homes/home-1/alarm', 'application/json',
                        '{"alarm_state":"alarm_stopped","device_timestamp":"2026-11-07T21:00:00.000Z"}'])
  end

  it 'sends Content-Type on POST and PUT only, as the data API does' do
    3.times { answer_empty }
    events.purge
    events.report(schema::TimelineEventsReport.new(events: []))
    events.delete_clip('clip-1')
    expect(cloud.requests.map { [it.verb, it.path.delete_prefix(timeline), it.headers['content-type'], it.body] })
      .to eq([['POST', '/purge', 'application/json', '{}'],
              ['PUT', '/report-events', 'application/json', '{"events":[]}'], ['DELETE', '/clips/clip-1', nil, '']])
  end

  it 'deletes events with the request it is given' do
    answer_empty
    deleted = schema::TimelineEventDelete.new(id: 'e-1', timestamp: 't')
    events.delete(schema::TimelineEventsDelete.new(events: [deleted]))
    expect(sent).to eq(['POST', "#{timeline}/delete-events", 'application/json',
                        '{"events":[{"id":"e-1","timestamp":"t"}]}'])
  end

  it 'reads the insights of a phone between two dates' do
    answer('home_stats' => [], 'device_notification_stats' => [])
    events.insights('phone-1', start_time: Time.utc(2026, 11, 1), end_time: Time.utc(2026, 11, 7))
    expect(cloud.requests.last.path).to eq('/data/insights/security/home-1/mobile-devices/phone-1?start_time=' \
                                           '2026-11-01T00%3A00%3A00.000Z&end_time=2026-11-07T00%3A00%3A00.000Z')
  end
end
