# frozen_string_literal: true

# Settings is a process-wide singleton: each example gets back the values it started with.
RSpec.configure do |config|
  config.around do |example|
    settings = Hue::Sdk.config
    saved = settings.instance_variables.to_h { |name| [name, settings.instance_variable_get(name)] }
    example.run
  ensure
    settings.instance_variables.each { |name| settings.remove_instance_variable(name) }
    saved.each { |name, value| settings.instance_variable_set(name, value) }
  end
end
