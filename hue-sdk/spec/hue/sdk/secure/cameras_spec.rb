# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::Cameras do
  subject(:cameras) { home.cameras }

  include_context 'with the Hue cloud'

  let(:path) { '/security/device-configuration/v1/home/home-1/device' }

  it 'lists the cameras from the reported body, keeping one it cannot read', :aggregate_failures do
    answer([{ 'reported' => { 'id' => 'cam-1', 'metadata' => { 'name' => 'Porte' } } },
            { 'reported' => { 'id' => 'cam-2', 'metadata' => 'Porte' } }])
    listed = cameras.list
    expect(sent).to eq(['GET', path, 'application/json', ''])
    expect(listed.map { [it.id, it.attributes&.metadata&.name] }).to eq([%w[cam-1 Porte], ['cam-2', nil]])
  end

  it 'reads one camera from the reported body', :aggregate_failures do
    answer('reported' => { 'id' => 'cam-1', 'enabled' => true })
    camera = cameras.get('cam-1')
    expect(sent).to eq(['GET', "#{path}/cam-1", 'application/json', ''])
    expect([camera.id, camera.data]).to eq(['cam-1', { 'id' => 'cam-1', 'enabled' => true }])
  end

  it 'sounds the speakers of the home together, for a duration in seconds' do
    answer_empty
    cameras.sound_group_alarm(duration: 30)
    expect(sent).to eq(['PUT', '/security/device-configuration/v2/home/home-1/grouped_speaker/command',
                        'application/json', '{"alarm":{"sound":"no_sound","duration":30000}}'])
  end

  it 'raises ResponseError on a partial group' do
    answer({}, 207)
    expect { cameras.sound_group_alarm(duration: 30) }
      .to raise_error(an_instance_of(Hue::Sdk::ResponseError).and(having_attributes(status: 207)))
  end
end
