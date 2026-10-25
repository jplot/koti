# frozen_string_literal: true

# Events server run in a child process, so a spec can starve it of file descriptors.
require 'miele/sdk'

Miele::Sdk.configure do |config|
  config.group_id = ENV.fetch('MIELE_GROUP_ID')
  config.group_key = ENV.fetch('MIELE_GROUP_KEY')
  config.read_timeout = 60
end
server = Miele::Sdk::Events::Server.new(port: 0, fab: '000000004321') { nil }
server.start
$stdout.sync = true
puts server.port
sleep
