# frozen_string_literal: true

module Ajax
  module Sdk
    module Cloud
      # A change to a followed space. +kind+ is +:space+ (a {Space}), +:security+ (its +SpaceSecurityMode+), +:group+
      # or +:room+ (their generated values, keyed by id), +:device+ (a {Device}, keyed as {Tracker} says) or
      # +:notification+ (a {Notification}, keyed by id). +before+ is nil for an addition, +after+ for a removal;
      # +state+ is the {SpaceState} once the message that brought the change is applied.
      Event = Data.define(:kind, :key, :before, :after, :state)

      # What is known of a space: its {Space} summary, its +SpaceSecurityMode+, and its groups, rooms and devices in
      # frozen Hashes by key.
      SpaceState = Data.define(:space, :security, :groups, :rooms, :devices)

      # Keeps the state of one space from the messages of its four streams and turns each message into the {Event}s
      # it brings. A snapshot is compared with the state kept, so a reconnection loses no change.
      #
      # A device is keyed as the app keys it: +[:hub_device, hub_id, device_id]+ (the hub itself has
      # +device_id == hub_id+), +[:video_edge, id]+, +[:video_edge_channel, video_edge_id, channel_id]+,
      # +[:smart_lock, id]+, +[:chime, id]+, or +[:access_cards_count]+, which gives no event.
      class Tracker
        LIGHT = Messages::Api::Ecosystem::V3::Mobilegwsvc::Commonmodels::Space::Device::Light
        SPACE = Messages::Api::Mobile::V2::Common::Space
        # Enough to give an updated notification what it was, and to tell a notification read again after a gap.
        KEPT = 500
        MESSAGES = {
          space: 'systems.ajax.api.mobile.v2.common.space.LiteSpace',
          security: 'systems.ajax.api.mobile.v2.common.space.security.SpaceSecurityMode',
          group: 'systems.ajax.api.mobile.v2.common.space.security.group.Group',
          room: 'systems.ajax.api.mobile.v2.common.space.room.Room',
          device: 'systems.ajax.api.ecosystem.v3.mobilegwsvc.commonmodels.space.device.light.LightDeviceItem',
          notification: 'systems.ajax.api.ecosystem.v2.communicationsvc.mobile.commonmodels.notification.Notification'
        }.freeze
        private_constant :LIGHT, :SPACE, :KEPT, :MESSAGES

        # The rules of +SpaceService/stream+ and +SpaceService/streamUserSpaces+.
        module SpaceRules
          TYPES = %i[SPACE_UPDATE_TYPE_ADD SPACE_UPDATE_TYPE_UPDATE SPACE_UPDATE_TYPE_REMOVE].freeze
          private_constant :TYPES

          private

          def space_message(raw)
            if (snapshot = raw[:snapshot])
              return [*put(:security, @space_id, snapshot.dig(:security, :mode)),
                      *replace(:group, by_id(snapshot.dig(:security, :groups))),
                      *replace(:room, by_id(snapshot[:rooms]))]
            end

            [raw[:update], *raw.dig(:updates, :updates)].compact.flat_map { space_update(it) }
          end

          # A REMOVE of the security mode is ignored, as the app has no handler for it.
          def space_update(update)
            type = update[:space_update_type]
            kind, entity = update.slice(:security_mode, :group, :room).first
            return [] unless TYPES.include?(type) && kind && entity

            removed = type == :SPACE_UPDATE_TYPE_REMOVE
            return removed ? [] : put(:security, @space_id, entity) if kind == :security_mode

            put(kind, entity[:id], (entity unless removed))
          end

          def summary_message(raw)
            initial = raw[:initial_state] or return lite_space_event(raw[:lite_space_event] || {})

            put(:space, @space_id, (initial[:spaces] || []).find { it[:id] == @space_id })
          end

          def lite_space_event(event)
            created = event.dig(:lite_space_created, :lite_space)
            updated = event[:lite_space_updated]
            if created&.dig(:id) == @space_id then put(:space, @space_id, created)
            elsif updated&.dig(:id) == @space_id then lite_space_update(updated)
            elsif event.dig(:lite_space_removed, :id) == @space_id then put(:space, @space_id, nil)
            else
              []
            end
          end

          def lite_space_update(updated)
            kept = @stores[:space][@space_id] or return []

            put(:space, @space_id, kept.merge(updated.except(:id)))
          end
        end

        # The rules of +stream_light_devices+.
        module DeviceRules
          UPSERT = %i[UPDATE_TYPE_ADD UPDATE_TYPE_UPDATE].freeze
          private_constant :UPSERT

          private

          def devices_message(raw)
            if (snapshot = raw[:snapshot])
              return replace(:device, (snapshot[:light_device_items] || []).to_h { [item_key(it), it] })
            end

            (raw.dig(:updates, :updates) || []).flat_map { device_update(it) }
          end

          def device_update(update)
            key = update_key(update[:device_id]) or return []
            kind, change = update.except(:device_id).first
            return snapshot_update(key, change) if kind == :snapshot_update

            item = @stores[:device][key]
            return [] unless item && kind

            put(:device, key, changed(item, kind, change))
          end

          def snapshot_update(key, change)
            return put(:device, key, change[:light_device_item] || {}) if UPSERT.include?(change[:update_type])

            change[:update_type] == :UPDATE_TYPE_REMOVE ? put(:device, key, nil) : []
          end

          def changed(item, kind, change)
            copy = Marshal.load(Marshal.dump(item))
            body = copy.values.first
            change_body(body, (body[:common_device] || body)[:profile], kind, change)
            copy
          end

          def change_body(body, profile, kind, change)
            case kind
            when :status_update then replace_status(profile, change)
            when :state_update then replace_state(profile, change)
            when :malfunctions_update then profile[:malfunctions] = change
            when :light_smart_lock_update then replace_lock(body, change[:spread_properties_update] || {})
            else replace_field(body, profile, change)
            end
          end

          def replace_status(profile, change)
            return unless typed?(change)

            kind = status_kind(change[:status] || {})
            statuses = (profile[:statuses] || []).reject { status_kind(it) == kind }
            profile[:statuses] = UPSERT.include?(change[:update_type]) ? [*statuses, change[:status] || {}] : statuses
          end

          # Statuses form a set by kind; a wire input has one per contact.
          def status_kind(status)
            name, body = status.first
            name == :wire_input_status ? [name, body[:contact_index].to_i] : [name]
          end

          def replace_state(profile, change)
            return unless typed?(change)

            states = (profile[:states] || []) - [change[:state]]
            profile[:states] = UPSERT.include?(change[:update_type]) ? [*states, change[:state]] : states
          end

          # The app ignores an ADD here.
          def replace_lock(body, change)
            case change[:update_type]
            when :UPDATE_TYPE_UPDATE then body[:spread_properties] = [change[:spread_property] || {}]
            when :UPDATE_TYPE_REMOVE then body[:spread_properties] = []
            end
          end

          def replace_field(body, profile, change)
            field, value = change.first
            case field
            when :spread_properties_update then replace_property(body, value)
            when :name, :room_id, :group_id then profile[field] = value
            else (body[:video_edge_channel_properties] ||= {})[field] = value
            end
          end

          def replace_property(body, change)
            return unless typed?(change)

            property = change[:spread_properties] || {}
            kind = property.keys - %i[id sort_index]
            kept = (body[:spread_properties] || []).reject { (it.keys - %i[id sort_index]) == kind }
            body[:spread_properties] = UPSERT.include?(change[:update_type]) ? [*kept, property] : kept
          end

          def typed?(change) = [*UPSERT, :UPDATE_TYPE_REMOVE].include?(change[:update_type])

          def item_key(item)
            wrapper, body = item.first
            profile = (body[:common_device] || body)[:profile] || {}
            case wrapper
            when :hub_device then [:hub_device, body.dig(:common_device, :hub_id), profile[:id]]
            when :video_edge_channel
              [wrapper, body.dig(:video_edge_channel_properties, :video_edge_id), profile[:id]]
            when :access_cards_count then [wrapper]
            else [wrapper, profile[:id]]
            end
          end

          def update_key(id)
            return unless id

            if (hub = id[:hub_light_device_id]) then [:hub_device, hub[:hub_id], hub[:device_id]]
            elsif (edge = id[:video_edge_id]) then [:video_edge, edge[:id]]
            elsif (channel = id[:video_edge_channel_reference])
              [:video_edge_channel, channel[:video_edge_id], channel[:channel_id]]
            elsif (lock = id[:smart_lock_id]) then [:smart_lock, lock[:id]]
            end
          end
        end

        include SpaceRules
        include DeviceRules

        # @param space_id [String]
        def initialize(space_id)
          @space_id = space_id
          @stores = { space: {}, security: {}, group: {}, room: {}, device: {}, notification: {} }
          @marks = nil
        end

        # @param source [Symbol] the stream the message came from: +:space+, +:summary+, +:devices+ or
        #   +:notifications+
        # @param success [Data] the success of one message of that stream
        # @return [Array<Event>] the changes it brings, in order
        def apply(source, success)
          raw = success.raw
          changes = case source
                    when :space then space_message(raw)
                    when :summary then summary_message(raw)
                    when :devices then devices_message(raw)
                    else (raw[:events] || []).flat_map { notification_event(it) }
                    end
          events(changes)
        end

        # @return [Array(Float, String), nil] the time and universal token of the newest notification seen outside a
        #   group, which a feed opened with this tracker reads back from
        def newest = @marks&.first

        # @api private
        # @return [Boolean] whether a feed has read the notifications of the space with this tracker
        def read? = !@marks.nil?

        # @api private
        # @param marks [Array<Array(Float, String)>] times and universal tokens of notifications seen
        # @return [void]
        def remember(marks) = @marks = ((@marks || []) + marks).max_by(1, &:first)

        # @return [SpaceState] the state kept, frozen
        def state
          @state ||= SpaceState.new(space: value(:space, @stores[:space][@space_id]),
                                    security: value(:security, @stores[:security][@space_id]),
                                    groups: values(:group), rooms: values(:room), devices: values(:device))
        end

        private

        def events(changes)
          changes.filter_map do |kind, key, before, after|
            before = value(kind, before)
            after = value(kind, after)
            Event.new(kind:, key:, before:, after:, state:) if before || after
          end
        end

        def notification_event(event)
          note = event[:notification_created] || event[:notification_updated] or return []
          changes = put(:notification, note[:id], note)
          notes = @stores[:notification]
          notes.delete(notes.min_by { |_, raw| moment(raw) }&.first) while notes.size > KEPT
          changes
        end

        def put(kind, key, raw)
          store = @stores.fetch(kind)
          before = store[key]
          return [] if same?(kind, before, raw)

          raw ? store[key] = raw : store.delete(key)
          @state = nil unless kind == :notification
          [[kind, key, before, raw]]
        end

        def replace(kind, fresh)
          store = @stores.fetch(kind)
          changes = (store.keys | fresh.keys).filter_map do |key|
            [kind, key, store[key], fresh[key]] unless same?(kind, store[key], fresh[key])
          end
          store.replace(fresh)
          @state = nil unless changes.empty?
          changes
        end

        def by_id(list) = (list || []).to_h { [it[:id], it] }

        # The gateway leaves defaults out and orders its lists its own way; what the rules write does neither.
        def same?(kind, left, right) = canonical(kind, left) == canonical(kind, right)

        def canonical(kind, raw)
          return unless raw

          message = Schemas.message(MESSAGES.fetch(kind))
          sorted(message.decode(message.encode(message.new(raw))).to_h)
        end

        def sorted(value)
          case value
          when Hash then value.transform_values { sorted(it) }
          when Array then value.map { sorted(it) }.sort_by(&:inspect)
          else value
          end
        end

        def moment(raw) = Decode.time(raw[:server_timestamp]).to_f

        def values(kind)
          @stores.fetch(kind).filter_map { |key, raw| (found = value(kind, raw)) && [key, found] }.to_h.freeze
        end

        def value(kind, raw)
          return unless raw

          case kind
          when :space then Space.from(raw)
          when :security then SPACE::Security::SpaceSecurityMode.from(raw)
          when :group then SPACE::Security::Group::Group.from(raw)
          when :room then SPACE::Room::Room.from(raw)
          when :device then Device.from(LIGHT::LightDeviceItem.from(raw), space_id: @space_id)
          else Notification.from(raw)
          end
        end
      end
    end
  end
end
