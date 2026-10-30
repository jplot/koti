# frozen_string_literal: true

require_relative 'java_names'

module Schema
  module Extract
    # The gRPC stubs of the app as jadx decompiles them: the service each stub class names, and each method with its
    # call type and the classes, often obfuscated, of its request and response.
    module GrpcStubs
      CALL_TYPES = { 'a' => :unary, 'b' => :client_stream, 'c' => :server_stream, 'd' => :bidi }.freeze
      SERVICE_NAME = /SERVICE_NAME = "([^"]+)"/
      GRPC_CLASS = /final class (\w+GrpcKt)/
      METHOD = /\.e = \w+\.([abcd]);\s*\n\s*\w+\.\w+ = \w+\.\w+\(([^,]+),\s*"(\w+)"\)/
      REQUEST = /([\w$]+) \w+ = \1\.getDefaultInstance\(\)/
      RESPONSE = /\.d = new \w+\(([\w$]+)\.getDefaultInstance\(\)\)/

      module_function

      # @return [Hash{String=>String}] each stub class to the full name of its service
      def service_names(source)
        name = source[SERVICE_NAME, 1]
        return {} unless name

        stubs = source.scan(/import defpackage\.(\w+);/).flatten.to_h { [it, name] }
        source[GRPC_CLASS, 1] ? stubs.merge(source[GRPC_CLASS, 1] => name) : stubs
      end

      # @return [Array<Array>] +[service, method, call type, request class, response class]+ for each method, the
      #   classes by their full names
      def rpcs(source, service_names)
        rows = []
        position = 0
        while (match = METHOD.match(source, position))
          position = match.end(0)
          next unless (service = service(match[2].strip, service_names))

          window = declarations(source, position)
          classes = [REQUEST, RESPONSE].map { message(window, it, source) }
          rows << [service, match[3], CALL_TYPES.fetch(match[1]), *classes]
        end
        rows
      end

      # A method's classes sit anywhere before the next one: capturePhoto declares its response 416 characters on.
      def declarations(source, from) = source[from...(METHOD.match(source, from)&.begin(0) || source.size)]

      def message(window, pattern, source) = JavaNames.qualify(window[pattern, 1], source)

      def service(holder, service_names)
        holder.start_with?('"') ? holder.delete('"') : service_names[holder.split('.').first]
      end
    end
  end
end
