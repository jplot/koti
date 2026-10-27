# frozen_string_literal: true

RSpec.describe Hue::Sdk::Models::Base do
  let(:light) { { id: 'l1', type: 'light', on: { on: true } } }
  let(:routes) do
    {
      'GET /clip/v2/resource/light' => { errors: [], data: [light] },
      'GET /clip/v2/resource/light/l1' => { errors: [], data: [light.merge(effects: { status: 'none' })] },
      'PUT /clip/v2/resource/light/l1' => { errors: [], data: [{ rid: 'l1', rtype: 'light' }] },
      'POST /clip/v2/resource/room' => { errors: [], data: [{ rid: 'r9', rtype: 'room' }] },
      'DELETE /clip/v2/resource/scene/s1' => { errors: [], data: [{ rid: 's1', rtype: 'scene' }] },
      'GET /clip/v2/resource/motion/m1' => {
        errors: [],
        data: [{ id: 'm1', type: 'motion',
                 motion: { motion: true, motion_valid: true, motion_report: { motion: true } } }]
      },
      'GET /clip/v2/resource/device/d1' => {
        errors: [],
        data: [{ id: 'd1', type: 'device', services: [{ rid: 'l1', rtype: 'light' }, { rid: 'x1', rtype: 'future' }] }]
      }
    }
  end
  let(:bridge) { FakeBridge.serving(routes) }

  before { connect_to(bridge) }
  after { bridge.stop }

  def gets = bridge.requests.count { |request| request.verb == 'GET' }

  it 'builds instances with preloaded data from list', :aggregate_failures do
    lights = Hue::Sdk.Light.list
    expect(lights.map { |instance| instance['on'] }).to eq([{ 'on' => true }])
    expect(gets).to eq(1)
  end

  it 'fetches data lazily, once' do
    instance = Hue::Sdk.Light('l1')
    2.times { instance.data }
    expect(gets).to eq(1)
  end

  it 'puts attributes on update and invalidates data', :aggregate_failures do
    instance = Hue::Sdk.Light('l1').tap(&:data)
    expect(instance.update(on: { on: false })).to be(instance)
    instance.data
    expect(bridge.requests.map { |request| [request.verb, request.body] })
      .to eq([['GET', nil], ['PUT', '{"on":{"on":false}}'], ['GET', nil]])
  end

  it 'posts on create and returns a lazy instance', :aggregate_failures do
    room = Hue::Sdk.Room.create(metadata: { name: 'Kitchen', archetype: 'kitchen' }, children: [])
    expect(room).to be_a(Hue::Sdk::Models::Room::Instance).and(have_attributes(id: 'r9'))
    expect(gets).to eq(0)
  end

  it 'puts a typed request on update' do
    Hue::Sdk.Light('l1').update(Hue::Sdk::Schema::LightUpdate.new(on: Hue::Sdk::Schema::OnFeatureUpdate.new(on: false)))
    expect(bridge.requests.last.body).to eq('{"on":{"on":false}}')
  end

  it 'posts a typed request on create' do
    metadata = Hue::Sdk::Schema::RoomMetadataAdd.new(name: 'Kitchen', archetype: 'kitchen')
    Hue::Sdk.Room.create(Hue::Sdk::Schema::RoomAdd.new(metadata:, children: []))
    expect(JSON.parse(bridge.requests.last.body))
      .to eq('metadata' => { 'name' => 'Kitchen', 'archetype' => 'kitchen' }, 'children' => [])
  end

  it 'issues a DELETE on delete' do
    expect(Hue::Sdk.Scene('s1').delete).to be(true)
  end

  it 'exposes no operation the API does not accept', :aggregate_failures do
    expect(Hue::Sdk.Light).not_to respond_to(:create)
    expect(Hue::Sdk.DevicePower('p1')).not_to respond_to(:update)
    expect(Hue::Sdk.Light('l1')).not_to respond_to(:delete)
  end

  it 'resolves services to typed instances' do
    expect(Hue::Sdk.Device('d1').services.first)
      .to be_a(Hue::Sdk::Models::Light::Instance).and(have_attributes(id: 'l1'))
  end

  it 'resolves an unknown resource type to a generic resource' do
    expect(Hue::Sdk.Device('d1').services.last)
      .to be_a(Hue::Sdk::Models::Resource::Instance).and(have_attributes(id: 'x1'))
  end

  it 'reads a resource as a typed value' do
    expect(Hue::Sdk.Light('l1').attributes.on).to eq(Hue::Sdk::Schema::OnFeature.new(on: true))
  end

  it 'gives no typed value to an unknown resource type' do
    expect(Hue::Sdk.Device('d1').services.last).not_to respond_to(:attributes)
  end

  it 'hides deprecated fields' do
    expect(Hue::Sdk.Light('l1').data).not_to have_key('effects')
  end

  it 'hides deprecated fields nested in an attribute' do
    expect(Hue::Sdk.Motion('m1')['motion']).to eq('motion_report' => { 'motion' => true })
  end
end
