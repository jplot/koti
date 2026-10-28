# frozen_string_literal: true

require_relative 'merge'
require_relative 'requests'
require_relative 'responses'

abort 'Usage: ruby schema/extract/build.rb BLUTTER_OUTPUT LIBAPP AIOHUE_MODELS CAPTURE' unless ARGV.size == 4

blutter, libapp, aiohue, capture = ARGV
objdump = Schema::Extract::Objdump.new(command: ENV.fetch('LLVM_OBJDUMP', 'llvm-objdump'), library: libapp)
snapshot = Schema::Extract::Snapshot.new(blutter, objdump)
responses = Schema::Extract::Responses.new(snapshot).read
merge = Schema::Extract::Merge.new(responses:, requests: Schema::Extract::Requests.new(snapshot, responses).read,
                                   aiohue: Schema::Extract::Aiohue.read(aiohue),
                                   capture: JSON.parse(File.read(capture)), models: Hue::Sdk::Models::REGISTRY)
puts JSON.pretty_generate(merge.schema)
warn merge.report
