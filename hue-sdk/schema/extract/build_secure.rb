# frozen_string_literal: true

require 'json'
require_relative 'secure'

abort 'Usage: ruby schema/extract/build_secure.rb BLUTTER_OUTPUT LIBAPP' unless ARGV.size == 2

blutter, libapp = ARGV
objdump = Schema::Extract::Objdump.new(command: ENV.fetch('LLVM_OBJDUMP', 'llvm-objdump'), library: libapp)
snapshot = Schema::Extract::Snapshot.new(blutter, objdump)
taken = []
files = Schema::Extract::SecureSchema::ROOTS.to_h do |file, roots|
  classes = Schema::Extract::SecureClasses.new(snapshot, taken:).read(roots)
  taken += classes.keys
  [file, classes.sort.to_h]
end
puts JSON.pretty_generate(files)
