# frozen_string_literal: true

require 'resolv'
require 'socket'

module Hue
  module Sdk
    # Finds Hue bridges on the local network over mDNS, without any cloud
    # service.
    module Discovery
      # A bridge announcing itself on the local network.
      #
      # @!attribute [r] name
      #   @return [String] service instance name (+Hue Bridge - 000001+)
      # @!attribute [r] host
      #   @return [String] IPv4 address, or the +.local+ hostname when none was announced
      # @!attribute [r] port
      #   @return [Integer] HTTPS port
      # @!attribute [r] bridge_id
      #   @return [String] bridge identifier, upper case, as expected in {Configuration::Settings#bridge_id}
      # @!attribute [r] model_id
      #   @return [String] model (+BSB003+ for the Bridge Pro)
      Bridge = Data.define(:name, :host, :port, :bridge_id, :model_id)

      SERVICE = '_hue._tcp.local'
      private_constant :SERVICE

      module_function

      # Asks the network for Hue bridges and collects the answers until the
      # timeout. The query leaves from an ephemeral port, so responders answer
      # by unicast (RFC 6762, section 6.7).
      #
      # @param timeout [Numeric] seconds to listen for answers
      # @param address [String] where to send the query
      # @param port [Integer] destination port of the query
      # @return [Array<Bridge>] each answering bridge once
      # @api public
      def discover(timeout:, address:, port:)
        socket = UDPSocket.new
        socket.send(query, 0, address, port)
        listen(socket, timeout).uniq(&:bridge_id)
      ensure
        socket&.close
      end

      # Extracts the bridges announced in an mDNS response.
      #
      # @param packet [String] raw DNS message
      # @return [Array<Bridge>]
      # @api public
      def parse(packet)
        message = Resolv::DNS::Message.decode(packet)
        bridges(message.answer + message.additional)
      rescue Resolv::DNS::DecodeError
        []
      end

      # @return [String] encoded PTR question for the Hue service
      # @api private
      def query
        message = Resolv::DNS::Message.new(0)
        message.add_question(SERVICE, Resolv::DNS::Resource::IN::PTR)
        message.encode
      end

      # @param socket [UDPSocket]
      # @param timeout [Numeric]
      # @return [Array<Bridge>]
      # @api private
      def listen(socket, timeout)
        deadline = now + timeout
        found = [] #: Array[Bridge]
        while (left = deadline - now).positive? && socket.wait_readable(left)
          found.concat(parse(socket.recvfrom(9000).first))
        end
        found
      end

      # @return [Float] monotonic clock, in seconds
      # @api private
      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # @param records [Array<Array>] every record of the message
      # @return [Array<Bridge>] one bridge per Hue service instance announced
      # @api private
      def bridges(records) = records.filter_map { |name, _, data| bridge(data.name, records) if pointer?(name, data) }

      # @return [Boolean] whether the record points to a Hue service instance
      # @api private
      def pointer?(name, data) = data.is_a?(Resolv::DNS::Resource::IN::PTR) && name.to_s == SERVICE

      # @param instance [Resolv::DNS::Name] service instance announced by the PTR record
      # @param records [Array<Array>] every record of the message
      # @return [Bridge, nil] nil when the instance lacks its SRV record
      # @api private
      def bridge(instance, records)
        srv = record(records, instance, Resolv::DNS::Resource::IN::SRV) or return
        txt = properties(records, instance)
        Bridge.new(name: instance.to_a.first.to_s, host: host(records, srv), port: srv.port,
                   bridge_id: txt['bridgeid'].to_s.upcase, model_id: txt['modelid'].to_s)
      end

      # @return [String] IPv4 address of the SRV target, or the target itself
      # @api private
      def host(records, srv) = (record(records, srv.target, Resolv::DNS::Resource::IN::A)&.address || srv.target).to_s

      # @return [Hash{String=>String}] +key=value+ pairs of the instance TXT record
      # @api private
      def properties(records, instance)
        record(records, instance, Resolv::DNS::Resource::IN::TXT)&.strings.to_a.to_h { it.split('=', 2) }
      end

      # @return [Resolv::DNS::Resource, nil] first record of that type for that name
      # @api private
      def record(records, name, type) = records.find { |owner, _, data| owner == name && data.is_a?(type) }&.last
    end
  end
end
