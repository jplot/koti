# frozen_string_literal: true

require 'socket'

module Miele
  module Sdk
    module Events
      # Receives the changes appliances push, for as long as a block runs.
      #
      # @example Print the next state change of every appliance
      #   hosts = Miele::Sdk.discover.map(&:host)
      #   Miele::Sdk.events(hosts:) { |event| p event }
      class Listener
        # @param hosts [Array<String>] addresses of the appliances to enroll
        # @param mdns_address [String] mDNS group to announce this host on
        # @param mdns_port [Integer]
        # @raise [ArgumentError] without any host
        def initialize(hosts:, mdns_address: '224.0.0.251', mdns_port: 5353)
          raise ArgumentError, 'no appliance to listen to' if hosts.empty?

          @appliances = hosts.map { Sdk.appliance(it) }
          @mdns_address = mdns_address
          @mdns_port = mdns_port
          @fab = Sdk.config.listener_fab
          @events = Thread::Queue.new
        end

        # Announces this host, enrolls the appliances, then yields each event on
        # the calling thread. When the block breaks or raises, the appliances are
        # withdrawn and the listener stops.
        #
        # @yieldparam event [Event]
        # @return [Enumerator::Lazy<Event>, Object] the events without a block, else what +break+ returns
        # @api public
        def each(&)
          return to_enum(:each).lazy unless block_given?

          stream(&)
        end

        private

        # @return [void]
        def stream
          open
          loop do
            event = @events.pop #: Event
            yield event
          end
        ensure
          close
        end

        # @return [void]
        def open
          server = @server = Server.new(port: Sdk.config.listener_port, fab: @fab) { @events << it }
          server.start
          host = Sdk.config.advertise_address || local_address
          advertiser = @advertiser = Advertiser.new(fab: @fab, host:, port: server.port, address: @mdns_address,
                                                    mdns_port: @mdns_port)
          advertiser.start
          @appliances.each { enroll(it, advertiser.hostname, server.port) }
        end

        # One appliance out of reach must not deprive the others of their events.
        #
        # @return [void]
        def enroll(appliance, callback_host, port)
          Enrollment.enroll(appliance, our_fab: @fab, callback_host:, port:)
        rescue Error => e
          warn "miele-sdk: no events from #{appliance.host}: #{e.message}"
        end

        # @return [void]
        def close
          @appliances.each { withdraw(it) }
          @advertiser&.stop
          @server&.stop
        end

        # A failure here must not hide the error that ended the stream, nor
        # leave the other appliances enrolled.
        #
        # @return [void]
        def withdraw(appliance)
          Enrollment.withdraw(appliance, our_fab: @fab)
        rescue Error => e
          warn "miele-sdk: subscriptions left on #{appliance.host}: #{e.message}"
        end

        # @return [String] local address that routes to the first appliance
        def local_address
          socket = UDPSocket.new
          socket.connect(@appliances.fetch(0).host, 80)
          socket.local_address.ip_address
        ensure
          socket&.close
        end
      end
    end
  end
end
