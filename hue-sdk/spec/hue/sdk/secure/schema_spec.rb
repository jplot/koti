# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::Schema do
  it 'reads the arm state and configuration of a home as the app does', :aggregate_failures do
    read = described_class::ArmDisarmResponse.from(
      'state' => { 'arm_state' => 'armed_away', 'trigger_time' => '2026-11-07T21:00:00Z',
                   'apply_time' => '2026-11-07T21:00:30Z', 'source' => { 'type' => 'user', 'id' => 'user-1' } },
      'config' => nil
    )
    expect(read.state.source).to eq(described_class::ArmDisarmStateSourceResponse.new(type: 'user', id: 'user-1'))
    expect(read.config).to be_nil
  end

  it 'reads both signals of an alarm, the light and the speaker' do
    expect(described_class::AlarmSignal.from('light' => 'on_off', 'speaker' => 'siren').to_body)
      .to eq(light: 'on_off', speaker: 'siren')
  end

  it 'sends a request without the keys left out, and refuses one missing a required key', :aggregate_failures do
    request = described_class::ArmDisarmScheduleActionInfoRequest
    expect(request.new(time: '22:00', arm_state: 'armed_stay').to_body).to eq(time: '22:00', arm_state: 'armed_stay')
    expect { request.new(time: '22:00', arm_state: nil).to_body }.to raise_error(ArgumentError, /arm_state/)
  end
end
