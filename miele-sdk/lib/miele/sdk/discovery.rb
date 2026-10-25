# frozen_string_literal: true

require 'resolv'
require 'ipaddr'
require 'socket'

module Miele
  module Sdk
    # Finds Miele@home appliances on the local network over mDNS, without any
    # cloud service.
    module Discovery
      # An appliance announcing itself on the local network.
      #
      # @!attribute [r] name
      #   @return [String] service instance name (+Miele H7164BP+)
      # @!attribute [r] host
      #   @return [String] IPv4 address, or the +.local+ hostname when none was announced
      # @!attribute [r] port
      #   @return [Integer] HTTP port
      # @!attribute [r] device_type
      #   @return [Integer] Miele device type (13: oven with microwave, 18: hood, 27: induction hob…)
      # @!attribute [r] group_id
      #   @return [String] GroupID of the household it belongs to, empty when it belongs to none
      # @!attribute [r] connection
      #   @return [Integer] connection state the appliance announces
      # @!attribute [r] pairing
      #   @return [Boolean] whether the appliance waits to be paired
      Appliance = Data.define(:name, :host, :port, :device_type, :group_id, :connection, :pairing)

      SERVICE = '_mieleathome._tcp.local'
      private_constant :SERVICE

      MULTICAST = IPAddr.new('224.0.0.0/4')
      private_constant :MULTICAST

      module_function

      # Asks the network for Miele appliances and collects the answers until
      # the timeout. Miele appliances ignore a query from an ephemeral port
      # (RFC 6762, section 6.7), so it leaves from the mDNS port, shared with
      # the system's responder, and the answers come back by multicast.
      #
      # @param timeout [Numeric] seconds to listen for answers
      # @param address [String] where to send the query
      # @param port [Integer] destination port of the query
      # @param listen_port [Integer] local port the query leaves from (default: 5353)
      # @return [Array<Appliance>] each answering appliance once
      # @api public
      def discover(timeout:, address:, port:, listen_port: 5353)
        socket = query_socket(address, listen_port)
        listen(socket, timeout) { socket.send(query, 0, address, port) }.uniq(&:host)
      ensure
        socket&.close
      end

      # Extracts the appliances announced in an mDNS response.
      #
      # @param packet [String] raw DNS message
      # @return [Array<Appliance>]
      # @api public
      def parse(packet)
        message = Resolv::DNS::Message.decode(unflush(packet))
        appliances(message.answer + message.additional)
      rescue Resolv::DNS::DecodeError
        []
      end

      # @param address [String] destination of the query
      # @param listen_port [Integer]
      # @return [UDPSocket] bound to +listen_port+, member of +address+ when it is a multicast group
      # @api private
      def query_socket(address, listen_port)
        socket = UDPSocket.new
        socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true) # steep:ignore ArgumentTypeMismatch
        socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEPORT, true) # steep:ignore ArgumentTypeMismatch
        socket.bind('0.0.0.0', listen_port)
        group = IPAddr.new(address)
        return socket unless MULTICAST.include?(group)

        membership = group.hton + IPAddr.new('0.0.0.0').hton
        socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, membership) # steep:ignore ArgumentTypeMismatch
        socket
      end

      # Multicast answers set the top bit of a record's class to flush caches
      # (RFC 6762, section 10.2), and queries set it on a question to ask for a
      # unicast answer (section 5.4); Resolv then decodes them as generic
      # records. Every Miele answer carries it.
      #
      # @param packet [String] raw DNS message
      # @return [String] the message with the top bit of every class cleared
      # @raise [Resolv::DNS::DecodeError] if the message is truncated
      # @api private
      def unflush(packet)
        bytes = packet.b
        questions, *records = bytes.unpack('@4n4').map(&:to_i)
        offset = questions.to_i.times.reduce(12) { |at, _| unflush_class(bytes, skip_name(bytes, at)) + 2 }
        records.sum.times { offset = unflush_record(bytes, offset) }
        bytes
      end

      # @param bytes [String] message being unflushed in place
      # @param offset [Integer] start of a resource record
      # @return [Integer] offset of the next record
      # @raise [Resolv::DNS::DecodeError] if the record runs past the message
      # @api private
      def unflush_record(bytes, offset)
        offset = skip_name(bytes, offset)
        raise Resolv::DNS::DecodeError, 'truncated record' if offset + 10 > bytes.bytesize

        unflush_class(bytes, offset)
        offset + 10 + bytes.unpack1('n', offset: offset + 8).to_i
      end

      # @param bytes [String] message being unflushed in place
      # @param offset [Integer] start of a type, followed by its class
      # @return [Integer] offset of the class
      # @raise [Resolv::DNS::DecodeError] if the class runs past the message
      # @api private
      def unflush_class(bytes, offset)
        raise Resolv::DNS::DecodeError, 'truncated class' if offset + 4 > bytes.bytesize

        bytes.setbyte(offset + 2, bytes.getbyte(offset + 2).to_i & 0x7F)
        offset + 2
      end

      # @param bytes [String]
      # @param offset [Integer] start of a domain name
      # @return [Integer] offset of the byte after the name
      # @raise [Resolv::DNS::DecodeError] if the name runs past the message
      # @api private
      def skip_name(bytes, offset)
        loop do
          length = bytes.getbyte(offset) or raise Resolv::DNS::DecodeError, 'truncated name'
          return offset + 2 if length >= 0xC0
          return offset + 1 if length.zero?

          offset += length + 1
        end
      end

      # @return [String] encoded PTR question for the Miele@home service
      # @api private
      def query
        message = Resolv::DNS::Message.new(0)
        message.add_question(SERVICE, Resolv::DNS::Resource::IN::PTR)
        message.encode
      end

      # @param socket [UDPSocket]
      # @param timeout [Numeric]
      # @yield sends the query, at each of {ask_times}
      # @return [Array<Appliance>]
      # @api private
      def listen(socket, timeout)
        start = now
        asks = ask_times(timeout)
        found = [] #: Array[Appliance]
        while (elapsed = now - start) < timeout
          yield asks.shift if asks.fetch(0, timeout) <= elapsed
          next unless socket.wait_readable([asks.fetch(0, timeout) - elapsed, 0].max)

          found.concat(parse(socket.recvfrom(9000).first))
        end
        found
      end

      # Wi-Fi does not retransmit multicast: the query is repeated, each gap
      # twice the previous one (RFC 6762, section 5.2).
      #
      # @param timeout [Numeric]
      # @return [Array<Integer>] seconds after the start at which the query is sent: 0, 1, 3, 7…
      # @api private
      def ask_times(timeout) = Array.new(timeout.ceil) { (1 << it) - 1 }.select { it < timeout }

      # @return [Float] monotonic clock, in seconds
      # @api private
      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # @param records [Array<Array>] every record of the message
      # @return [Array<Appliance>] one appliance per service instance announced
      # @api private
      def appliances(records)
        records.filter_map { |name, _, data| appliance(data.name, records) if pointer?(name, data) }
      end

      # @return [Boolean] whether the record points to a Miele@home service instance
      # @api private
      def pointer?(name, data) = data.is_a?(Resolv::DNS::Resource::IN::PTR) && name.to_s == SERVICE

      # @param instance [Resolv::DNS::Name] service instance announced by the PTR record
      # @param records [Array<Array>] every record of the message
      # @return [Appliance, nil] nil when the instance lacks its SRV record
      # @api private
      def appliance(instance, records)
        srv = record(records, instance, Resolv::DNS::Resource::IN::SRV) or return
        txt = properties(records, instance)
        Appliance.new(name: instance.to_a.first.to_s, host: host(records, srv), port: srv.port,
                      device_type: txt['devicetype'].to_i, group_id: txt['group'].to_s,
                      connection: txt['con'].to_i, pairing: txt['pairing'] == 'true')
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
