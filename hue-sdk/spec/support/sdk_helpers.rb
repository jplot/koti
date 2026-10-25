# frozen_string_literal: true

# Points the SDK at a FakeBridge.
module SdkHelpers
  def connect_to(bridge, application_key: 'test-key')
    Hue::Sdk.configure do |config|
      config.host = '127.0.0.1'
      config.port = bridge.port
      config.bridge_id = 'ECB5FAFFFE000001'
      config.ca_file = bridge.ca_file
      config.application_key = application_key
    end
  end
end

RSpec.configure { |config| config.include SdkHelpers }
