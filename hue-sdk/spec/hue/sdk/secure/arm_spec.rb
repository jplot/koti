# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::Arm do
  subject(:arm) { home.arm }

  include_context 'with the Hue cloud'

  let(:schema) { Hue::Sdk::Secure::Schema }
  let(:mode) do
    schema::ArmDisarmModeConfigRequest.new(entry_delay: 30, exit_delay: 60, device: [],
                                           alarm_signal: { light: 'flash' })
  end

  {
    'reads the arm state and configuration' => [-> { arm.read }, 'GET', 'arm', ''],
    'reads the arm state' => [-> { arm.state }, 'GET', 'arm/state', ''],
    'sets the arm state' => [-> { arm.set_state('armed_away') }, 'PUT', 'arm/state', '{"arm_state":"armed_away"}'],
    'sounds the alarm with the one body the app sends' => [-> { arm.sound_alarm }, 'PUT', 'alarm',
                                                           '{"desired_state":"alarming"}'],
    'removes the arming of the home' => [-> { arm.remove }, 'DELETE', 'arm', ''],
    'deletes the geofence configuration' => [-> { arm.delete_geofence_config }, 'DELETE', 'arm/config/geofence', ''],
    'deletes the geofence configuration for presence' => [-> { arm.delete_geofence_config(:presence) }, 'DELETE',
                                                          'arm/config/geofence/presence', ''],
    'deletes the geofence configuration for an empty home' => [-> { arm.delete_geofence_config(:empty) }, 'DELETE',
                                                               'arm/config/geofence/empty', '']
  }.each do |behaviour, (call, verb, path, body)|
    it "#{behaviour} as the app does" do
      answer('state' => nil, 'config' => nil)
      instance_exec(&call)
      expect(sent).to eq([verb, "/security/arm-manager/v1/home/home-1/#{path}", 'application/json', body])
    end
  end

  it 'updates the configuration with the request it is given' do
    answer_empty
    arm.update_config(schema::ArmDisarmSetConfigRequest.new(armed_away: mode, armed_stay: mode))
    json = '{"entry_delay":30,"exit_delay":60,"device":[],"alarm_signal":{"light":"flash"}}'
    expect(sent).to eq(['PUT', '/security/arm-manager/v1/home/home-1/arm/config', 'application/json',
                        "{\"armed_away\":#{json},\"armed_stay\":#{json}}"])
  end

  it 'reads the state alone, and nil for a home without Hue Secure', :aggregate_failures do
    answer('arm_state' => 'armed_stay', 'trigger_time' => 't', 'apply_time' => 'a',
           'source' => { 'type' => 'user', 'id' => 'u' })
    answer(nil)
    expect(arm.state.arm_state).to eq('armed_stay')
    expect(arm.state).to be_nil
  end

  it 'reads the arm state and configuration of a home without Hue Secure' do
    answer('state' => nil, 'config' => nil)
    expect(arm.read).to eq(schema::ArmDisarmResponse.new(state: nil, config: nil))
  end

  it 'sends delay in seconds as a query' do
    answer_empty
    arm.set_state('armed_away', delay: 30)
    expect(cloud.requests.last.path).to eq('/security/arm-manager/v1/home/home-1/arm/state?delay=30')
  end

  it 'raises ResponseError on a partial alarm' do
    answer({}, 207)
    expect { arm.sound_alarm }
      .to raise_error(an_instance_of(Hue::Sdk::ResponseError).and(having_attributes(status: 207)))
  end

  it 'checks a request before sending it', :aggregate_failures do
    request = schema::ArmDisarmSetConfigRequest.new(armed_away: mode, armed_stay: nil)
    expect { arm.update_config(request) }.to raise_error(ArgumentError, /armed_stay/)
    expect(cloud.requests).to be_empty
  end
end
