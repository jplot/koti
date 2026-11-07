# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::Schedules do
  subject(:schedules) { home.schedules }

  include_context 'with the Hue cloud'

  let(:schema) { Hue::Sdk::Secure::Schema }
  let(:week) do
    action = schema::ArmDisarmScheduleActionInfoRequest.new(time: '22:00', arm_state: 'armed_stay')
    [schema::ArmDisarmScheduleConfigurationRequest.new(days: %w[monday], actions: [action])]
  end
  let(:path) { '/security/arm-manager/v1/home/home-1/arm/schedules' }

  it 'lists the schedules as the app reads them', :aggregate_failures do
    action = { 'time' => '22:00', 'arm_state' => 'armed_stay' }
    answer([{ 'id' => 's-1', 'name' => 'Nuit', 'active' => true,
              'schedules' => [{ 'days' => %w[monday], 'actions' => [action] }] }])
    listed = schedules.list
    expect(sent).to eq(['GET', path, 'application/json', ''])
    expect(listed.first.schedules.first.actions.first.arm_state).to eq('armed_stay')
  end

  it 'creates a schedule and gives its id', :aggregate_failures do
    answer('id' => 's-2')
    expect(schedules.create(schema::CreateArmDisarmScheduleRequest.new(name: 'Nuit', active: true, schedules: week)))
      .to eq('s-2')
    expect(sent).to eq(['POST', path, 'application/json',
                        '{"name":"Nuit","active":true,"schedules":[{"days":["monday"],' \
                        '"actions":[{"time":"22:00","arm_state":"armed_stay"}]}]}'])
  end

  it 'updates a schedule with only what changes' do
    answer_empty
    schedules.update('s-1', schema::UpdateArmDisarmScheduleRequest.new(active: false))
    expect(sent).to eq(['PUT', "#{path}/s-1", 'application/json', '{"active":false}'])
  end

  it 'deletes a schedule' do
    answer_empty
    schedules.delete('s-1')
    expect(sent).to eq(['DELETE', "#{path}/s-1", 'application/json', ''])
  end
end
