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
    answer('state' => nil, 'config' => nil)
    answer_empty
    arm.update_config(schema::ArmDisarmSetConfigRequest.new(armed_away: mode, armed_stay: mode))
    json = '{"entry_delay":30,"exit_delay":60,"device":[],"alarm_signal":{"light":"flash"}}'
    expect(sent).to eq(['PUT', '/security/arm-manager/v1/home/home-1/arm/config', 'application/json',
                        "{\"armed_away\":#{json},\"armed_stay\":#{json}}"])
  end

  describe 'a motion area in or out of arming' do
    let(:area) { { type: 'motion_area', id: 'area-1', bridge: 'br-1' } }
    let(:plans) do
      { 'free_tier' => { xp_end_date: '2000-01-01T00:00:00Z' },
        'experience_period_not_enabled' => { xp_enabled: false },
        'subscribed' => { subscription_ids: ['sub-1'] },
        'experience_period' => { xp_end_date: '2999-01-01T00:00:00Z' } }
    end

    def armed(*stay) = { 'state' => nil, 'config' => { 'armed_stay' => { 'device' => stay }, 'armed_away' => nil } }

    def bridge(status)
      entry = plans[status]&.then { [{ rid: 'BR-1', rtype: 'bridge', subscription_ids: [], xp_enabled: true, **it }] }
      { subscriptions: [], devices: entry || [] }
    end

    def update(*stay)
      arm.update_config(schema::ArmDisarmSetConfigRequest.new(armed_stay: mode.with(device: stay), armed_away: mode))
    end

    def puts = cloud.requests.count { it.verb == 'PUT' }

    %w[free_tier experience_period_not_enabled].each do |status|
      it "refuses it in or out while its bridge is #{status}, and sends nothing", :aggregate_failures do
        [[[], [area]], [[area], []]].each do |before, after|
          answer(armed(*before))
          answer(bridge(status))
          expect { update(*after) }
            .to raise_error(an_instance_of(Hue::Sdk::Secure::PlanError)
                              .and(having_attributes(rid: 'br-1', status: status.to_sym)))
        end
        expect(puts).to eq(0)
      end
    end

    %w[subscribed experience_period unknown].each do |status|
      it "lets it in while its bridge is #{status}" do
        answer(armed)
        answer(bridge(status))
        answer_empty
        update(area)
        expect(cloud.requests.map(&:verb)).to eq(%w[GET GET PUT])
      end
    end

    it 'sends one kept where it was without reading the plans' do
      answer(armed(area))
      answer_empty
      update(area)
      expect(cloud.requests.map(&:path)).to eq(['/security/arm-manager/v1/home/home-1/arm',
                                                '/security/arm-manager/v1/home/home-1/arm/config'])
    end

    it 'sends nothing when the plans cannot be read', :aggregate_failures do
      answer(armed)
      answer({}, 500)
      expect { update(area) }.to raise_error(Hue::Sdk::ResponseError)
      expect(puts).to eq(0)
    end
  end

  describe 'a camera detection the alarm picks' do
    let(:homes) do
      home = FakeHomes.message(1 => 'home-1', 4 => FakeHomes.message(1 => 'br-1'),
                               6 => FakeHomes.message(1 => 'CMB001', 2 => 'cam-1'))
      FakeHomes.start { FakeHomes.field(1, home) }
    end
    let(:people) { { type: 'people', id: 'cam-1' } }
    let(:paid) do
      { rid: 'sub-1', user: { rid: 'user-1' }, subscription_product: { rid: 'hue.security.basic.single.yearly' },
        homes: [{ rid: 'home-1' }], scope: {}, subscription_state: 'active', provider: 'web',
        start_date: '2026-01-01T00:00:00Z' }
    end

    before do
      Hue::Sdk::Secure.configure do |config|
        config.grpc_target = homes.target
        config.grpc_credentials = :this_channel_is_insecure
      end
    end

    after { homes.stop }

    def picked(*entities) = { 'config' => { 'armed_stay' => { 'alarm_triggering_entities' => entities } } }

    def pick(*entities)
      stay = mode.with(alarm_triggering_entities: entities)
      arm.update_config(schema::ArmDisarmSetConfigRequest.new(armed_stay: stay, armed_away: mode))
    end

    it 'refuses a person, a pet or a vehicle unless a plan or a trial covers the home, and sends nothing',
       :aggregate_failures do
      %w[people pet vehicle].each do |type|
        answer(picked)
        answer(subscriptions: [], devices: [])
        expect { pick({ type:, id: 'cam-1' }) }
          .to raise_error(an_instance_of(Hue::Sdk::Secure::PlanError)
                            .and(having_attributes(rid: 'home-1', status: nil)))
      end
      expect(cloud.requests.count { it.verb == 'PUT' }).to eq(0)
    end

    it 'picks one under a paid plan of the home, without listing the homes', :aggregate_failures do
      answer(picked)
      answer(subscriptions: [paid], devices: [])
      answer_empty
      pick(people)
      expect([cloud.requests.last.verb, homes.calls.size]).to eq(['PUT', 0])
    end

    it 'picks one while a camera of the home is in its trial' do
      answer(picked)
      answer(subscriptions: [], devices: [{ rid: 'cam-1', rtype: 'camera', subscription_ids: [], xp_enabled: true,
                                            xp_end_date: '2999-01-01T00:00:00Z' }])
      answer_empty
      pick(people)
      expect(cloud.requests.last.verb).to eq('PUT')
    end

    it 'keeps one already picked, drops one, and picks common objects, without reading the plans' do
      answer(picked(people.transform_keys(&:to_s), { 'type' => 'pet', 'id' => 'cam-1' }))
      answer_empty
      pick(people, { type: 'common_object', id: 'cam-2' })
      expect(cloud.requests.map(&:verb)).to eq(%w[GET PUT])
    end
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
