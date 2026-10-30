# frozen_string_literal: true

require 'rbs'
require_relative '../../../schema/generate/methods'

RSpec.describe Schema::Generate::Methods do
  subject(:source) { described_class.rbs(Schema::Generate::Model.load(schemas)) }

  let(:schemas) { File.expand_path('../../../lib/ajax/sdk/cloud/schemas', __dir__) }

  it 'returns the success of an outcome response, through an Enumerator for a stream', :aggregate_failures do
    v2 = '::Ajax::Sdk::Cloud::Messages::Api::Mobile::V2'
    expect { RBS::Parser.parse_signature(source) }.not_to raise_error
    expect(source).to include("def space_security_arm_group: (?space_locator: #{v2}::Common::Space::SpaceLocator?, " \
                              "?group_id: ::String, ?ignore_alarms: bool) -> #{v2}::Common::Response::Success")
    expect(source).to match(/stream_light_devices: \(.*\) -> ::Enumerator\[\S+DevicesResponse::Success, nil\]/)
  end
end
