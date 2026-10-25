# frozen_string_literal: true

require 'resolv'
require 'socket'

module Miele
  module Sdk
    module Events
      # Announces this host on mDNS as a peer of the household, so that the
      # appliances find where to push their changes.
      class Advertiser
        SERVICE = '_mieleathome._tcp.local'
        private_constant :SERVICE

        TTL = 120
        private_constant :TTL

        IN = Resolv::DNS::Resource::IN
        private_constant :IN

        # @param fab [String] fabrication number this host takes in the household
        # @param host [String] IPv4 address the appliances reach this host at
        # @param port [Integer] port of the {Server}
        # @param address [String] mDNS group to answer on
        # @param mdns_port [Integer] port to answer on
        def initialize(fab:, host:, port:, address: '224.0.0.251', mdns_port: 5353)
          @fab = fab
          @host = host
          @port = port
          @address = address
          @mdns_port = mdns_port
        end

        # @return [String] service instance name
        # @api public
        def instance = "koti #{@fab}.#{SERVICE}"

        # Kept stable per fabrication number, since appliances cache mDNS records.
        #
        # @return [String] host name in the form the appliances use for themselves
        # @api public
        def hostname = format('Miele-001D63FFFE%<low>06X.local', low: @fab[-8..].to_i & 0xFFFFFF)

        # @return [Integer] port the advertiser answers on
        # @api public
        def port = @socket.local_address.ip_port

        # Joins the mDNS group, announces this host and answers queries for it.
        #
        # @return [void]
        # @api public
        def start
          @socket = Discovery.query_socket(@address, @mdns_port)
          @socket.send(response(0, records), 0, @address, port)
          @thread = Thread.new { serve }
        end

        # @return [void]
        # @api public
        def stop
          @thread&.kill
          @socket&.close
        end

        private

        # @return [void]
        def serve
          loop do
            packet, from = @socket.recvfrom(9000)
            reply = answer(packet, from[1])
            host, to = from[1] == 5353 ? [@address, port] : [from[3], from[1]]
            @socket.send(reply, 0, host, to) if reply
          end
        rescue IOError
          nil
        end

        # @param packet [String]
        # @param source_port [Integer]
        # @return [String, nil] the encoded answer, nil when the query asks for nothing of ours
        def answer(packet, source_port)
          query = Resolv::DNS::Message.decode(Discovery.unflush(packet))
          return if query.qr == 1

          matches = query.question.flat_map { |name, type| matching(name.to_s, type) }
          return if matches.empty?

          # Legacy unicast (RFC 6762, section 6.7): the querier only reads answers carrying its id and question.
          legacy = source_port != 5353
          response(legacy ? query.id : 0, matches, records - matches, legacy ? query.question : [])
        rescue Resolv::DNS::DecodeError
          nil
        end

        # @param name [String]
        # @param type [Class]
        # @return [Array<Array(String, Integer, Resolv::DNS::Resource)>]
        def matching(name, type) = records.select { |owner, _, data| owner == name && data.is_a?(type) }

        # @return [Array<Array(String, Integer, Resolv::DNS::Resource)>] PTR, SRV, TXT and A records of this host
        def records
          @records ||= [[SERVICE, TTL, IN::PTR.new(Resolv::DNS::Name.create("#{instance}."))],
                        [instance, TTL, IN::SRV.new(0, 0, @port, Resolv::DNS::Name.create("#{hostname}."))],
                        [instance, TTL, IN::TXT.new(*properties)], [hostname, TTL, IN::A.new(@host)]]
        end

        # @return [Array<String>] TXT +key=value+ pairs, the ones the appliances announce
        def properties
          { txtvers: 1, group: Sdk.config.group_id, path: '/', security: 1, pairing: false, devicetype: DEVICE_TYPE,
            con: 2, subtype: 0, s: 0 }.map { |key, value| "#{key}=#{value}" }
        end

        # @param id [Integer]
        # @param answers [Array<Array(String, Integer, Resolv::DNS::Resource)>]
        # @param additional [Array<Array(String, Integer, Resolv::DNS::Resource)>]
        # @param questions [Array<Array(Resolv::DNS::Name, Class)>]
        # @return [String]
        def response(id, answers, additional = [], questions = [])
          message = Resolv::DNS::Message.new(id)
          message.qr = 1
          message.aa = 1
          questions.each { |name, type| message.add_question(name.to_s, type) }
          answers.each { |name, ttl, data| message.add_answer("#{name}.", ttl, data) }
          additional.each { |name, ttl, data| message.add_additional("#{name}.", ttl, data) }
          message.encode
        end
      end
    end
  end
end
