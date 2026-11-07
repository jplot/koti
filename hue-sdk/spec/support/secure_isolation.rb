# frozen_string_literal: true

require 'hue/sdk/secure'

# The Hue Secure settings and session are process-wide: each example gets back the settings it started with, and
# no session.
RSpec.configure do |config|
  config.around do |example|
    settings = Hue::Sdk::Secure.config
    saved = settings.instance_variables.to_h { |name| [name, settings.instance_variable_get(name)] }
    example.run
  ensure
    settings.instance_variables.each { |name| settings.remove_instance_variable(name) }
    saved.each { |name, value| settings.instance_variable_set(name, value) }
    Hue::Sdk::Secure.configure { nil }
  end
end
