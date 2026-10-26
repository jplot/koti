# frozen_string_literal: true

module Ajax
  module Sdk
    module Cloud
      # A space (one hub and its devices) as the app lists it: its id, its hub, its name, its security
      # state and whether the hub is online. +raw+ keeps the whole decoded Hash for the rest.
      Space = Data.define(:id, :hub_id, :name, :security_state, :online, :raw) do
        # @param raw [Hash] one entry of findUserSpacesWithPagination
        # @return [Space]
        def self.from(raw)
          new(id: raw[:id], hub_id: raw[:hub_id], name: raw.dig(:profile, :name),
              security_state: raw[:security_state].to_s.sub(/\ADISPLAYED_SPACE_SECURITY_STATE_/, '').downcase.to_sym,
              online: raw[:hub_connection_status] == :CONNECTION_STATUS_ONLINE, raw:)
        end
      end

      # The named cloud reads and commands, mixed into {Client}: listing spaces, reading devices and
      # history, and arming or disarming a space.
      module Resources
        V2 = 'systems.ajax.api.mobile.v2'
        GW = 'systems.ajax.api.ecosystem.v3.mobilegwsvc.service'
        SECURITY = "/#{V2}.space.security.SpaceSecurityService".freeze
        SPACES = "/#{V2}.space.SpaceService/findUserSpacesWithPagination".freeze
        DEVICES = "/#{GW}.stream_light_devices.StreamLightDevicesService/execute".freeze
        NOTIFICATIONS = "/#{V2}.notification.NotificationLogService/findNotifications".freeze
        private_constant :V2, :GW, :SECURITY, :SPACES, :DEVICES, :NOTIFICATIONS

        # @return [Array<Space>] every space of the account, across every page
        # @raise [ReadError] when the gateway refuses the read
        def spaces
          found = [] #: Array[Hash[Symbol, untyped]]
          request = {} #: Hash[Symbol, untyped]
          loop do
            page = success!(call(SPACES, request))
            found.concat(page[:spaces] || [])
            token = page.dig(:pagination, :forward_exclusive_pagination_token).to_s
            return found.map { |raw| Space.from(raw) } if token.empty?

            request = { pagination: { forward_exclusive_pagination_token: token } }
          end
        end

        # @param id [String] a space id
        # @return [Space, nil]
        def space(id) = spaces.find { |candidate| candidate.id == id }

        # @return [Array<Hash>] the devices of +space_id+ with their status, as a first snapshot
        # @raise [ReadError] when the gateway refuses the read
        def devices(space_id)
          snapshot = success!(server_stream(DEVICES, { space_id: }).first || {})
          snapshot.dig(:snapshot, :light_device_items) || []
        end

        # @param space_id [String]
        # @param limit [Integer] how many to read back
        # @return [Array<Hash>] recent notifications of the space, most recent first
        # @raise [ReadError] when the gateway refuses the read
        def notifications(space_id, limit: 50)
          success!(call(NOTIFICATIONS, { filter: { origin: { space_id: } }, limit: }))[:notifications] || []
        end

        # @return [void] arm the space
        def arm(space_id, ignore_alarms: false) = command("#{SECURITY}/arm", space_id, ignore_alarms:)

        # @return [void] disarm the space
        def disarm(space_id) = command("#{SECURITY}/disarm", space_id)

        # @return [void] arm the space to night mode
        def arm_night(space_id, ignore_alarms: false) = command("#{SECURITY}/armToNightMode", space_id, ignore_alarms:)

        # @return [void] disarm the space from night mode
        def disarm_night(space_id) = command("#{SECURITY}/disarmFromNightMode", space_id)

        private

        def command(path, space_id, ignore_alarms: nil)
          raise ReadOnlyError, "#{path} refused: the client is read-only" if read_only?

          request = space_locator(space_id)
          request[:ignore_alarms] = ignore_alarms unless ignore_alarms.nil?
          answer = call(path, request)
          return if answer[:success]

          raise CommandError, refusal(answer[:failure])
        end

        def refusal(failure) = (failure || {}).keys.first || :refused

        def space_locator(space_id) = { space_locator: { space_id: } }

        def success!(answer) = answer[:success] || raise(ReadError, refusal(answer[:failure]))
      end
    end
  end
end
