# frozen_string_literal: true

require 'json'

module Miele
  module Sdk
    module Events
      # Makes an appliance push its changes to this host, and stops it.
      module Enrollment
        RESOURCES = %w[/State/ /State/Light/ /State/Status/ /Ident/].freeze
        private_constant :RESOURCES

        module_function

        # Declares this host a supervising peer, then subscribes it to each
        # pushed resource of the appliance.
        #
        # @param appliance [Appliance]
        # @param our_fab [String] fabrication number this host takes
        # @param callback_host [String] host name the appliance reaches this host at
        # @param port [Integer] port of the {Server}
        # @return [void]
        # @raise [Error] if the appliance refuses a subscription
        # @api public
        def enroll(appliance, our_fab:, callback_host:, port:)
          supervise(appliance, our_fab, true)
          RESOURCES.each do |resource|
            callback = "http://#{callback_host}:#{port}/Devices/#{our_fab}/SuperVision/#{appliance.fab}#{resource}"
            body = JSON.generate(Resource: "/Devices/#{appliance.fab}#{resource}", Callback: callback)
            Connection.request(appliance.host, :post, '/Subscriptions', body:)
          end
        end

        # Deletes every subscription calling this host back, whichever run made it.
        #
        # @param appliance [Appliance]
        # @param our_fab [String]
        # @return [void]
        # @raise [Error]
        # @api public
        def withdraw(appliance, our_fab:)
          supervise(appliance, our_fab, false)
          appliance.get('/Subscriptions/').each_key do |slot|
            next unless appliance.get("/Subscriptions/#{slot}/")['Callback'].to_s.include?("/Devices/#{our_fab}/")

            Connection.request(appliance.host, :delete, "/Subscriptions/#{slot}/")
          end
        end

        # A basic appliance has no SuperVision and answers 404; one already in
        # the requested state answers 400.
        #
        # @return [void]
        # @api private
        def supervise(appliance, our_fab, on)
          Connection.request(appliance.host, :put, "/Devices/#{appliance.fab}/SuperVision/#{our_fab}",
                             body: JSON.generate(Show: on, Signal: on))
        rescue ResponseError => e
          raise unless [400, 404].include?(e.status)
        end
      end
    end
  end
end
