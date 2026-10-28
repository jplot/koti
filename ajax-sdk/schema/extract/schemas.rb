# frozen_string_literal: true

require 'zlib'
require_relative 'grpc_stubs'
require_relative 'java_literals'
require_relative 'linker'

module Schema
  module Extract
    # Rebuilds the cloud schemas of lib/ajax/sdk/cloud/schemas/ from the app as jadx decompiles it: the protobuf
    # descriptors its generated Java carries, and the method table its gRPC stubs give.
    module Schemas
      module_function

      # @param roots [Array<String>] directories of jadx sources
      # @return [Integer] the number of methods paired; the others are listed on stderr
      def write(roots, directory)
        sources = read(roots)
        descriptors = sources.values.flat_map { JavaLiterals.descriptors(it) }.uniq
        linker = Linker.new(descriptors, sources.transform_keys { File.basename(it, '.java') })
        write_descriptors(File.join(directory, 'descriptors.pb.gz'), descriptors)
        File.open(File.join(directory, 'methods.tsv'), 'w') { table(it, rpcs(sources.values), linker) }
      end

      # @return [Hash{String=>String}] each .java file to its text
      def read(roots)
        roots.flat_map { Dir.glob(File.join(it, '**', '*.java')) }.to_h { [it, File.read(it, encoding: Encoding::UTF_8)] }
      end

      def rpcs(texts)
        services = texts.reduce({}) { |all, text| all.merge(GrpcStubs.service_names(text)) }
        texts.flat_map { GrpcStubs.rpcs(it, services) }.uniq
      end

      # A FileDescriptorSet holds each file as field 1, so its bytes go in unchanged.
      def write_descriptors(path, descriptors)
        Zlib::GzipWriter.open(path) { |gzip| descriptors.each { gzip.write("\x0A".b, varint(it.bytesize), it) } }
      end

      def varint(value) = value < 0x80 ? value.chr : ((value & 0x7F) | 0x80).chr + varint(value >> 7)

      def table(tsv, rows, linker)
        rows.sort_by { it.first(3) }.count do |service, method, type, request, response|
          pair = linker.pair(service, method, request, response)
          next warn("unpaired\t#{service}\t#{method}") unless pair

          tsv.puts(["/#{service}/#{method}", type, *pair].join("\t"))
          true
        end
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  roots = ARGV.take_while { it != '--out' }
  abort 'Usage: ruby schema/extract/schemas.rb JADX_SOURCES... --out DIRECTORY' unless ARGV.index('--out')
  warn "paired #{Schema::Extract::Schemas.write(roots, ARGV.fetch(ARGV.index('--out') + 1))} methods"
end
