# frozen_string_literal: true

require 'json'
require_relative 'behaviors'

abort 'Usage: ruby schema/extract/build_behaviors.rb BLUTTER_OUTPUT LIBAPP BEHAVIORS_DIRECTORY' unless ARGV.size == 3

blutter, libapp, behaviors = ARGV
objdump = Schema::Extract::Objdump.new(command: ENV.fetch('LLVM_OBJDUMP', 'llvm-objdump'), library: libapp)
snapshot = Schema::Extract::Snapshot.new(blutter, objdump)
taken = JSON.parse(File.read(File.join(__dir__, '..', 'hue.json'))).fetch('classes').keys
classes = Schema::Extract::BehaviorClasses.new(snapshot, taken:).read(Schema::Extract::BehaviorSchema::ROOTS)
scripts = Schema::Extract::BehaviorScripts.new(behaviors, snapshot).read
puts JSON.pretty_generate(Schema::Extract::BehaviorSchema.compose(scripts:, classes:))
