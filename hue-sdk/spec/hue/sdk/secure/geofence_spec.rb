# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::Geofence do
  subject(:geofence) { home.geofence }

  include_context 'with the Hue cloud'

  let(:request) do
    Hue::Sdk::Secure::Schema::UpdateGeofenceClientRequest.new(presence: true, name: 'Téléphone', bridge: 'bridge-1',
                                                              geofence_client_id: 'client-1')
  end
  let(:path) { '/security/geofence-service/v1/home/home-1/geofence/client' }
  let(:body) { '{"presence":true,"name":"Téléphone","bridge":"bridge-1","geofence_client_id":"client-1"}' }

  it 'lists the geofence clients as the app reads them', :aggregate_failures do
    answer([{ 'name' => 'Téléphone', 'presence' => true, 'bridge_data' => { 'bridge-1' => 'client-1' },
              'mobile_app_id' => 'phone-1' }])
    listed = geofence.list
    expect(sent).to eq(['GET', path, 'application/json', ''])
    expect(listed.first.bridge_data).to eq('bridge-1' => 'client-1')
  end

  {
    'creates' => [:create, 'POST'], 'updates' => [:update, 'PUT']
  }.each do |behaviour, (method, verb)|
    it "#{behaviour} the geofence client of a phone" do
      answer_empty
      geofence.public_send(method, 'phone-1', request)
      expect(sent).to eq([verb, "#{path}/phone-1", 'application/json', body])
    end
  end

  it 'deletes the geofence client of a phone' do
    answer_empty
    geofence.delete('phone-1')
    expect(sent).to eq(['DELETE', "#{path}/phone-1", 'application/json', ''])
  end

  it 'deletes the client of a phone on one bridge' do
    answer_empty
    geofence.delete_bridge_client('phone-1', 'client-1')
    expect(sent).to eq(['DELETE', "#{path}/phone-1/bridge-client/client-1", 'application/json', ''])
  end
end
