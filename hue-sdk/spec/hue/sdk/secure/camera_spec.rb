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

  it 'reads what the cloud reported as the app does, and keeps what it cannot read', :aggregate_failures do
    read = described_class.new('home-1', 'cam-1', 'id' => 'cam-1', 'metadata' => { 'name' => 'Porte' })
    unread = described_class.new('home-1', 'cam-2', 'id' => 'cam-2', 'metadata' => 'Porte')
    expect(read.attributes.metadata.name).to eq('Porte')
    expect([unread.attributes, unread.data]).to eq([nil, { 'id' => 'cam-2', 'metadata' => 'Porte' }])
  end
end
