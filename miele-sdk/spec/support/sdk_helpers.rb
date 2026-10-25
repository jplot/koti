# frozen_string_literal: true

# Points the SDK at a FakeAppliance.
module SdkHelpers
  def connect_to(appliance)
    Miele::Sdk.configure do |config|
      config.port = appliance.port
      config.group_id = FakeAppliance::GROUP_ID
      config.group_key = FakeAppliance::GROUP_KEY
    end
  end
end

RSpec.configure { |config| config.include SdkHelpers }
