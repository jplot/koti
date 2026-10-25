# frozen_string_literal: true

require 'net/http'

# Points the SDK at a FakeAppliance.
module SdkHelpers
  def connect_to(appliance)
    Miele::Sdk.configure do |config|
      config.port = appliance.port
      config.group_id = FakeAppliance::GROUP_ID
      config.group_key = FakeAppliance::GROUP_KEY
    end
  end

  # Sends a request signed and encrypted as an appliance does, to a local events server.
  def deliver(port, verb, path, body = '', group_key: FakeAppliance::GROUP_KEY)
    request = Net::HTTP.const_get(verb.capitalize).new(path)
    Miele::Sdk::Connection.sign(request, '127.0.0.1', body.empty? ? '' : Miele::Sdk::Crypto.pad(body),
                                [FakeAppliance::GROUP_ID].pack('H*'), [group_key].pack('H*'))
    Net::HTTP.start('127.0.0.1', port, read_timeout: 5) { it.request(request) }
  end
end

RSpec.configure { |config| config.include SdkHelpers }
