# frozen_string_literal: true

require 'json'

module Miele
  module Sdk
    module Cloud
      # The Miele cloud as a channel to the account's appliances: each appliance's own paths, under +/V2+.
      class Channel
        TYPES = { json: 'application/vnd.miele.v1+json', dop2: 'application/vnd.miele.v1+dop2' }.freeze
        private_constant :TYPES

        # An appliance of the account, as the cloud lists it.
        #
        # @!attribute [r] fab
        #   @return [String] fabrication number
        # @!attribute [r] host
        #   @return [String] mDNS name of its Wi-Fi module, which names it on Dop1 requests
        # @!attribute [r] ident
        #   @return [Hash{String=>Object}] its +Ident+
        # @!attribute [r] state
        #   @return [Hash{String=>Object}] its +State+
        Device = Data.define(:fab, :host, :ident, :state)

        # @return [Session]
        attr_reader :session

        # @param session [Session]
        def initialize(session)
          @session = session
        end

        # @param method [Symbol] +:get+, +:put+, +:post+ or +:delete+
        # @param path [String] the appliance's own path, query included
        # @param body [String, nil]
        # @param kind [Symbol] +:json+ or +:dop2+, the type of the body
        # @param host [String, nil] the module's mDNS name, which the cloud routes a Dop1 request by
        # @return [Connection::Response]
        # @raise [NotFoundError, RemoteControlDisabledError, ResponseError] on an error status, a 401 too: the token
        #   is kept and the request not sent again, as by the app's appliance client (MieleHttpClientHandler)
        # @raise [ConnectionError] if the cloud cannot be reached
        # @api public
        def request(method, path, body: nil, kind: :json, host: nil)
          headers = { 'Content-Type' => (TYPES.fetch(kind) if body), 'Host' => host&.delete_suffix('.') }.compact
          exchange(@session.current, method, path, body, headers)
        end

        # @return [Array<Device>] the appliances paired with the account
        # @raise [AuthenticationError] on a 401 or 403, once logged out with the token forgotten ({Session#invalidate}):
        #   the app stops observing its appliance list and loses the session (PairedAppliancesRepository
        #   OnObservationError, AppLifeCycleViewModel.PairedAppliancesRepository_OnAuthorizationError)
        # @raise [ResponseError] on any other error status
        # @api public
        def devices
          JSON.parse(listed(@session.current).body).flat_map do |wifi|
            devices = wifi['devices'] || [] #: Array[Hash[String, untyped]]
            devices.map do |device|
              Device.new(fab: device.fetch('mac'), host: wifi.fetch('host'), ident: device['ident'],
                         state: device['state'])
            end
          end
        end

        # @return [Array(String, String)] GroupID and GroupKey of the account's household, as hexadecimal digits
        # @raise [NotFoundError] when the account has none
        # @api public
        def group
          first = JSON.parse(request(:get, '/GroupKeyId/').body).first
          raise NotFoundError.new(404, 'the account has no household key') unless first

          [first.fetch('groupId'), first.fetch('groupKey')]
        end

        private

        # @return [Connection::Response]
        def exchange(token, method, path, body, headers)
          headers = { 'Authorization' => "#{token.scheme} #{token.value}", 'Accept-Language' => @session.language,
                      **headers }
          answer = Http.request(method, "#{@session.organization.rest}/V2#{path}", headers:, body:)
          refuse(answer.status, method) unless answer.status.between?(200, 299)
          Connection::Response.new(status: answer.status, body: answer.body)
        end

        # @param token [Token]
        # @return [Connection::Response]
        def listed(token)
          exchange(token, :get, '/Devices', nil, {})
        rescue ResponseError => e
          raise unless [401, 403].include?(e.status)

          @session.invalidate(token)
          raise AuthenticationError, "the Miele cloud refused the appliance list (#{e.status}): the session is lost"
        end

        # @param status [Integer]
        # @param method [Symbol]
        # @return [void]
        # @raise [NotFoundError, RemoteControlDisabledError, ResponseError]
        def refuse(status, method)
          raise NotFoundError.new(status, "cloud answered #{status}") if status == 404
          raise ResponseError.new(status, "cloud answered #{status}") unless status == 403 && method != :get

          raise RemoteControlDisabledError.new(status, 'the appliance refused the command: enable remote control on it')
        end
      end
    end
  end
end
