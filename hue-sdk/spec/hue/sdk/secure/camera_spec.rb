# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::Camera do
  subject(:camera) { described_class.new('home-1', 'cam-1', {}) }

  include_context 'with the Hue cloud'

  let(:schema) { Hue::Sdk::Secure::Schema }
  let(:device) { '/security/device-configuration/v1/home/home-1/device/cam-1' }
  let(:speaker) { '/security/device-configuration/v2/home/home-1/device/cam-1/service/speaker/0/command' }

  {
    'renames or disables the camera' => [-> { camera.update(schema::CameraConfigUpdate.new(enabled: false)) },
                                         '', '{"enabled":false}'],
    'updates its camera service' => [
      -> { camera.update_camera(schema::CameraCameraServiceUpdate.new(video_quality: 'high', hdr: true)) },
      '/service/camera/0', '{"video_quality":"high","hdr":true}'
    ],
    'updates its microphone' => [-> { camera.update_microphone(schema::CameraMicrophoneUpdate.new(enabled: true)) },
                                 '/service/microphone/0', '{"enabled":true}'],
    'mutes one of its speakers' => [
      -> { camera.update_speaker('speaker-1', schema::CameraSpeakerUpdate.new(mute: { mute: true })) },
      '/service/speaker/speaker-1', '{"mute":{"mute":true}}'
    ],
    'sets the chime of one of its bell buttons' => [
      -> { camera.update_bell_button('button-1', schema::CameraBellButtonUpdate.new(chime: { sound: 'ding' })) },
      '/service/bell_button/button-1', '{"chime":{"sound":"ding"}}'
    ],
    'sets its motion sensitivity' => [
      -> { camera.update_motion(schema::CameraMotionSensitivityUpdate.new(sensitivity: 3)) },
      '/service/motion/0', '{"sensitivity":3}'
    ],
    'renames a device linked to it' => [
      -> { camera.update_linked_device('chime-1', schema::CameraLinkedDeviceUpdate.new(metadata: { archetype: 'x' })) },
      '/linked_device/chime-1', '{"metadata":{"archetype":"x"}}'
    ],
    'takes a snapshot' => [-> { camera.snapshot }, '/service/camera/0/command', '{"action_type":"snapshot"}'],
    'wakes it up' => [-> { camera.wake_up }, '/command', '{"action_type":"wake_up"}'],
    'reboots it' => [-> { camera.reboot }, '/command', '{"action_type":"reboot"}'],
    'resets its settings' => [-> { camera.reset }, '/default_settings', '']
  }.each do |behaviour, (call, path, body)|
    it "#{behaviour} as the app does" do
      answer_empty
      instance_exec(&call)
      expect(sent).to eq(['PUT', "#{device}#{path}", 'application/json', body])
    end
  end

  it 'sends a setting the app would gate by plan as it is given, reading nothing first', :aggregate_failures do
    2.times { answer_empty }
    camera.update_camera(schema::CameraCameraServiceUpdate.new(video_quality: 'high', clips_recording: true))
    camera.update_microphone(schema::CameraMicrophoneUpdate.new(smoke_alarm_detection: { enabled: true }))
    expect(cloud.requests.map(&:verb)).to eq(%w[PUT PUT])
  end

  it 'uses v2 for the speaker commands, with a 10 s siren and the chime volume in hundredths', :aggregate_failures do
    2.times { answer_empty }
    camera.sound_chime(sound: 'ding', volume: 0.29)
    chime = sent
    camera.sound_alarm
    expect(chime).to eq(['PUT', speaker, 'application/json', '{"chime":{"sound":"ding","volume":{"level":29}}}'])
    expect(sent).to eq(['PUT', speaker, 'application/json', '{"alarm":{"sound":"siren","duration":10000}}'])
  end

  it 'sounds a chime without a volume, as the app may' do
    answer_empty
    camera.sound_chime(sound: 'ding')
    expect(cloud.requests.last.body).to eq('{"chime":{"sound":"ding"}}')
  end

  it 'raises ResponseError when the camera is out of reach', :aggregate_failures do
    2.times { answer({}, 521) }
    expect { camera.wake_up }
      .to raise_error(an_instance_of(Hue::Sdk::ResponseError).and(having_attributes(status: 521)))
    expect { camera.sound_alarm }.to raise_error(Hue::Sdk::ResponseError)
  end

  describe '#detections' do
    let(:four) { %w[people pet vehicle common_object] }

    def detections(zones, service: { 'camera' => { '0' => { 'activity_zones' => zones } } }, **body)
      data = { 'id' => 'cam-1', 'metadata' => {}, 'product_data' => { 'model_id' => 'CMB001' }, 'service' => service }
      described_class.new('home-1', 'cam-1', data.merge(body)).detections
    end

    def zone(types, entire_area: false, area: [{ 'x' => 0.1, 'y' => 0.2 }])
      { 'entire_area' => entire_area, 'detection_type' => types, 'area' => area }
    end

    it 'offers all four without activity zones, as the app reads a camera over HTTP', :aggregate_failures do
      expect([detections(nil), detections([]), detections(nil, service: {})]).to all(eq(four))
    end

    it 'offers what a single zone over the entire area detects, one that says nothing too', :aggregate_failures do
      expect(detections([zone(%w[pet], entire_area: true, area: nil)])).to eq(%w[pet])
      expect(detections([zone(nil, entire_area: true, area: nil)])).to eq([])
      expect(detections([{ 'detection_type' => %w[vehicle] }])).to eq(%w[vehicle])
    end

    it "offers what any custom zone detects, in the order of the app's rows", :aggregate_failures do
      expect(detections([zone(%w[vehicle]), zone(%w[vehicle people]), zone(nil)])).to eq(%w[people vehicle])
      expect(detections([zone(%w[pet])])).to eq(%w[pet])
    end

    it 'gives nil where the app cannot convert the zones, and adds no row for the camera', :aggregate_failures do
      expect(detections([zone(%w[dog])])).to be_nil
      expect(detections([zone(%w[dog], entire_area: true, area: nil)])).to be_nil
      expect(detections([zone(%w[people]), zone(%w[dog])])).to be_nil
      expect(detections([zone(%w[people], area: nil)])).to be_nil
      expect(detections([zone(%w[people]), zone(%w[pet], area: nil)])).to be_nil
      expect(detections([zone(%w[people], entire_area: true, area: nil), zone(%w[pet], area: nil)])).to be_nil
    end

    it 'offers nothing where the app cannot decode the camera but still lists it', :aggregate_failures do
      broken = { 'camera' => { '0' => { 'activity_zones' => {} } } }
      [nil, 'x', broken].each { expect(detections(nil, 'service' => it)).to eq([]) }
      [[nil], [{ 'detection_type' => 'people' }], [{ 'detection_type' => [1] }]]
        .each { expect(detections(it)).to eq([]) }
    end

    it 'gives nil for a camera the app cannot list at all', :aggregate_failures do
      expect(detections(nil, 'service' => nil, 'metadata' => 'x')).to be_nil
      expect(detections(nil, 'service' => nil, 'product_data' => {})).to be_nil
    end
  end

  it 'reads what the cloud reported as the app does, and keeps what it cannot read', :aggregate_failures do
    read = described_class.new('home-1', 'cam-1', 'id' => 'cam-1', 'metadata' => { 'name' => 'Porte' })
    unread = described_class.new('home-1', 'cam-2', 'id' => 'cam-2', 'metadata' => 'Porte')
    expect(read.attributes.metadata.name).to eq('Porte')
    expect([unread.attributes, unread.data]).to eq([nil, { 'id' => 'cam-2', 'metadata' => 'Porte' }])
  end
end
