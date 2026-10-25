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

  it 'hides deprecated fields' do
    expect(Hue::Sdk.Light('l1').data).not_to have_key('effects')
  end
end
