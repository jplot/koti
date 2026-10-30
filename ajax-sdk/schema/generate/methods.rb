# frozen_string_literal: true

require_relative 'model'
require_relative 'ruby'
require_relative 'rbs'
require_relative 'index'

module Schema
  module Generate
    # Writes methods.rb and methods.rbs: a method of +Client+ for each method of methods.tsv, named after its path.
    module Methods
      STREAMS = %i[server_stream bidi].freeze
      BATCHES = %i[client_stream bidi].freeze

      module_function

      # @return [String] methods.rb
      def ruby(model)
        methods = model.calls.flat_map { ['', *doc(model, it), definition(it)] }.drop(1)
        body = ['# The methods of the app 3.59, each named after its gRPC path. Mixed into {Client}.', 'module Methods',
                *Ruby.indent(methods), 'end']
        [Ruby::HEADER, *Index.wrap(body), ''].join("\n")
      end

      # @return [String] methods.rbs
      def rbs(model)
        methods = model.calls.flat_map { signature(model, it) }
        body = ['module Methods', *Ruby.indent(methods), '', '  # Provided by Client, used here.',
                '  def call: (::String path, ?untyped request) ?{ (untyped) -> void } -> untyped', 'end']
        [Rbs::HEADER, '', *Index.wrap(body), ''].join("\n")
      end

      def doc(model, call)
        result = relative(returned(model, call))
        ["# +#{call.path}+, a #{call.type.to_s.tr('_', ' ')} call.", '#', parameter(call),
         *(STREAMS.include?(call.type) ? stream(result) : ["# @return [#{result}]"]),
         *('# @raise [RefusedError] when the gateway answers a failure' if call.response.outcome)]
      end

      def parameter(call)
        request = relative("::#{call.request.constant}")
        return "# @param requests [Array<#{request}, Hash>] the request messages" if BATCHES.include?(call.type)

        "# @param request [Hash{Symbol=>Object}] the members of {#{request}}"
      end

      def stream(returned)
        ["# @yieldparam message [#{returned}] each message",
         '# @return [Enumerator, nil] an Enumerator of the messages when no block is given']
      end

      def relative(constant) = constant.delete_prefix("#{Ruby::CLOUD}::")

      def definition(call)
        block = ', &' if STREAMS.include?(call.type)
        given, sent = arguments(call)
        "def #{call.name}(#{given}#{block}) = call('#{call.path}', #{sent}#{block})"
      end

      def arguments(call)
        BATCHES.include?(call.type) ? %w[requests requests] : ['**request', "::#{call.request.constant}.new(**request)"]
      end

      def signature(model, call)
        result = returned(model, call)
        given = parameters(model, call)
        return ["def #{call.name}: (#{given}) -> #{result}"] unless STREAMS.include?(call.type)

        ["def #{call.name}: (#{given}) -> ::Enumerator[#{result}, nil]",
         "#{' ' * (call.name.size + 4)}| (#{given}) { (#{result}) -> void } -> nil"]
      end

      def parameters(model, call)
        request = "::#{call.request.constant}"
        return "::Array[#{request} | ::Hash[::Symbol, untyped]] requests" if BATCHES.include?(call.type)

        call.request.fields.map { "?#{it.name}: #{Rbs.type_of(model, it)}" }.join(', ')
      end

      # The success of a response whose +success+ shares a oneof with its +failure+, as Outcome.settle gives it.
      def returned(model, call)
        response = call.response
        return "::#{response.constant}" unless response.outcome

        Rbs.base(model, response.fields.find { it.name == :success })
      end
    end
  end
end
