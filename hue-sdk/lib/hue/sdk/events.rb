# frozen_string_literal: true

require 'json'
require 'time'

module Hue
  module Sdk
    Event = Data.define(:id, :kind, :created_at, :resource_type, :resource_id, :changes)

    # A change on the bridge, delivered by {Sdk.events}.
    #
    # @!attribute [r] id
    #   @return [String] event id, shared by the resources changed together
    # @!attribute [r] kind
    #   @return [Symbol] +:add+, +:update+, +:delete+ or +:error+
    # @!attribute [r] created_at
    #   @return [Time] when the bridge emitted the event
    # @!attribute [r] resource_type
    #   @return [String] type of the changed resource (+light+, +motion+…)
    # @!attribute [r] resource_id
    #   @return [String] id of the changed resource
    # @!attribute [r] changes
    #   @return [Hash{String=>Object}] the attributes that changed
    class Event
      # @return [Models::Base::Instance] the changed resource, loaded on first access
      # @api public
      def resource = Sdk.resource(resource_type, resource_id)
    end

    # Server-sent events of the bridge.
    module Events
      # Splits a server-sent event stream into messages.
      class Parser
        # @api public
        def initialize
          @buffer = ''.b
          @data = []
          @id = nil
        end

        # @param chunk [String] bytes read from the stream, cut anywhere
        # @yieldparam message [Hash{Symbol=>String}] +id+ and +data+ of each complete message
        # @return [void]
        # @api public
        def feed(chunk, &)
          @buffer << chunk.b
          while (line = @buffer.slice!(/\A[^\n]*\n/))
            field, value = line.chomp.force_encoding(Encoding::UTF_8).split(/: ?/, 2)
            case field
            when nil then dispatch(&)
            when 'id' then @id = value
            when 'data' then @data << value.to_s
            end
          end
        end

        private

        # @yieldparam message [Hash{Symbol=>String}]
        # @return [void]
        # @api private
        def dispatch
          return if @data.empty?

          data = @data.join("\n")
          @data = []
          yield({ id: @id, data: })
        end
      end

      # Follows the event stream of the bridge, reconnecting when it breaks.
      class Stream
        PATH = '/eventstream/clip/v2'
        MAX_DELAY = 30
        private_constant :PATH, :MAX_DELAY

        # @param sleeper [#call] waits the given number of seconds before a reconnection
        # @api public
        def initialize(sleeper: method(:sleep))
          @sleeper = sleeper
          @last_id = nil
          @delay = 1
        end

        # Blocks and yields every event. After a network failure or the end of
        # the stream, reconnects after 1, 2, 4, 8, 16 then 30 seconds, back to
        # 1 second once a message arrives.
        #
        # @yieldparam event [Event]
        # @return [void]
        # @raise [AuthenticationError] if no application key is configured or the bridge rejects it
        # @raise [ConnectionError] if no host is configured
        # @raise [TLSError] if the bridge certificate is not trusted
        # @raise [ResponseError] if the bridge answers with another error status
        # @api public
        def each(&)
          key = Sdk.config.application_key or raise AuthenticationError, 'application_key is not configured'
          Sdk.config.host or raise ConnectionError, 'host is not configured'
          loop do
            follow(key, &)
            wait
          rescue ConnectionError
            wait
          end
        end

        private

        # @param key [String] application key
        # @yieldparam event [Event]
        # @return [void]
        # @api private
        def follow(key, &)
          parser = Parser.new
          response = Connection.stream(PATH, headers: headers(key)) do |chunk|
            parser.feed(chunk) do |message|
              @delay = 1
              @last_id = message[:id]
              events(message[:data]).each(&)
            end
          end
          refuse(response) unless response.is_a?(Net::HTTPOK)
        end

        # @param key [String] application key
        # @return [Hash{String=>String}]
        # @api private
        def headers(key)
          { 'hue-application-key' => key, 'Accept' => 'text/event-stream', 'Last-Event-ID' => @last_id }.compact
        end

        # @return [void]
        # @api private
        def wait
          @sleeper.call(@delay)
          @delay = [@delay * 2, MAX_DELAY].min
        end

        # @param data [String] JSON array of event containers
        # @return [Array<Event>] one event per changed resource
        # @api private
        def events(data)
          JSON.parse(data).flat_map do |container|
            id = container['id']
            kind = container['type'].to_sym
            created_at = Time.iso8601(container['creationtime'])
            container['data'].map do |resource|
              Event.new(id:, kind:, created_at:, resource_type: resource['type'], resource_id: resource['id'],
                        changes: resource.except('id', 'type'))
            end
          end
        end

        # @param response [Net::HTTPResponse]
        # @return [void]
        # @raise [AuthenticationError, ResponseError]
        # @api private
        def refuse(response)
          status = response.code.to_i
          raise AuthenticationError, "bridge rejected the application key (#{status})" if [401, 403].include?(status)

          raise ResponseError.new(status, [])
        end
      end
    end
  end
end
