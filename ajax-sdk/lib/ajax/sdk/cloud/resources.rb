# frozen_string_literal: true

require_relative 'decode'
require_relative 'device'
require_relative 'notification'

module Ajax
  module Sdk
    module Cloud
      # A space (one hub and its devices) as the app lists it: its id, its hub, its name, its security
      # state and whether the hub is online. +raw+ keeps the whole decoded Hash for the rest.
      Space = Data.define(:id, :hub_id, :name, :security_state, :online, :raw) do
        # @param raw [Hash] one entry of findUserSpacesWithPagination
        # @return [Space]
        def self.from(raw)
          new(id: raw[:id].to_s, hub_id: raw[:hub_id], name: raw.dig(:profile, :name).to_s,
              security_state: Decode.enum(raw[:security_state], 'DISPLAYED_SPACE_SECURITY_STATE_'),
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
          found = [] #: Array[untyped]
          request = {} #: Hash[Symbol, untyped]
          loop do
            page = call(SPACES, request)
            found.concat(page.spaces)
            token = page.pagination&.forward_exclusive_pagination_token.to_s
            return found.map { Space.from(it.raw) } if token.empty?

            request = { pagination: { forward_exclusive_pagination_token: token } }
          end
        end

        # @param id [String] a space id
        # @return [Space, nil]
        def space(id) = spaces.find { |candidate| candidate.id == id }

        # @return [Array<Device>] the devices of +space_id+ with their status, as a first snapshot
        # @raise [ReadError] when the gateway refuses the read
        def devices(space_id)
          first = server_stream(DEVICES, { space_id: }).first or raise ReadError, :refused
          (first.snapshot&.light_device_items || []).filter_map { Device.from(it, space_id:) }
        end

        # @param space_id [String]
        # @param limit [Integer] how many to read back; the app never asks for more than 20
        # @param older_than [String, nil] the {Notification#token} of a notification outside an offline group, to
        #   read those before it
        # @param newer_than [String, nil] the {Notification#token} of a notification outside an offline group, to
        #   read those after it
        # @return [Array<Notification>] one page of the space's notifications, with those grouped under an offline
        #   one (their {Notification#parent_id} set), most recent first
        # @raise [ArgumentError] when given both tokens
        # @raise [ReadError] when the gateway refuses the read
        def notifications(space_id, limit: 20, older_than: nil, newer_than: nil)
          newest_first(notification_page(space_id, limit:, older_than:, newer_than:))
        end

        # @param space_id [String]
        # @param limit [Integer] the size of each page read; a gateway that sends fewer ends the history there
        # @return [Enumerator::Lazy<Notification>] every notification of the space, a page at a time, each page most
        #   recent first
        # @raise [ReadError] when the gateway refuses a read
        def notification_history(space_id, limit: 20)
          Enumerator.new do |out|
            older_than = nil
            loop do
              page = newest_first(notification_page(space_id, limit:, older_than:))
              page.each { out << it }
              top = page.reject(&:parent_id)
              break if top.empty? || top.size < limit

              older_than = top.last&.token
            end
          end.lazy
        end

        # Follows the space live through one feed of {Event}s: its security, groups, rooms, summary, devices and
        # notifications, from four streams. The feed ends when one of them ends and raises what breaks one: reopen it
        # with the same tracker to get the changes made meanwhile, and nothing else. See {Feed}.
        #
        # @param space_id [String]
        # @param tracker [Tracker, nil] the state kept from an earlier feed of the space, for one feed at a time; a new
        #   one by default
        # @yieldparam event [Event]
        # @return [Enumerator::Lazy<Event>, nil] the events when no block is given
        # @raise [RefusedError] when a stream answers a failure
        # @raise [GRPC::BadStatus] when a stream breaks
        def events(space_id, tracker: nil, &)
          return enum_for(:events, space_id, tracker:).lazy unless block_given?

          Feed.new(self, space_id, tracker: tracker || Tracker.new(space_id)).each(&)
          nil
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
          request = space_locator(space_id)
          request[:ignore_alarms] = ignore_alarms unless ignore_alarms.nil?
          call(path, request)
          nil
        end

        def space_locator(space_id) = { space_locator: { space_id: } }

        # The app pages from the token of a notification it holds, never from next_*_pagination_token, and ends on
        # a page short of notifications outside an offline group.
        def notification_page(space_id, limit:, older_than: nil, newer_than: nil)
          raise ArgumentError, 'give older_than or newer_than, not both' if older_than && newer_than

          pagination = ({ forward_pagination_token: older_than } if older_than) ||
                       ({ backward_pagination_token: newer_than } if newer_than)
          page = call(NOTIFICATIONS, { filter: { origin: { space_id: } }, limit:, pagination: }.compact)
          grouped = page.offline_notifications_data.flat_map do |group|
            group.notifications.map { Notification.from(it.raw, parent_id: group.parent_notification_id) }
          end
          page.notifications.map { Notification.from(it.raw) } + grouped
        end

        def newest_first(notifications) = notifications.sort_by { -it.time.to_f }
      end
    end
  end
end
