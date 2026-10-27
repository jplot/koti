# frozen_string_literal: true

module Ajax
  module Sdk
    module Cloud
      # The battery of a device. +charge+ is a percentage; when +exact+ is false the device only tells
      # a charged battery from a discharged one, and the app shows « OK » from 21 and « discharged »
      # below instead of the number. +state+ is +:ok+, +:warning+, +:alert+, +:error+,
      # +:en54_warning+ or +:unspecified+.
      Battery = Data.define(:state, :charge, :exact) do
        # @param raw [Hash{Symbol=>Object}] the +battery+ status of a device
        # @return [Battery]
        def self.from(raw)
          new(state: Decode.enum(raw[:battery_state], 'BATTERY_STATE_'), charge: raw[:charge_level_percentage].to_i,
              exact: !raw[:is_without_charge])
        end
      end

      # A device of a space, from the devices snapshot.
      #
      # +kind+ is the device type for a device of the hub (+:door_protect_plus+, +:hub_two_4g+…), or the
      # item for the others (+:smart_lock+, +:video_edge+…). +hub_id+ is nil outside the hub. +states+
      # holds +:offline+, +:locked+, +:updating+… +battery+, +signal+ (+:no_signal+, +:weak+, +:normal+,
      # +:strong+, +:disconnected+) and +temperature+ (°C) are nil when the device does not report them.
      # +flags+ lists the statuses that carry no value (+:door_opened+, +:leak_detected+,
      # +:armed_in_night_mode+…); the statuses with a value other than these three stay in +raw+.
      Device = Data.define(:id, :name, :kind, :hub_id, :room_id, :group_id, :states, :malfunctions, :bypassed,
                           :battery, :signal, :temperature, :flags, :raw) do
        # @param item [Hash{Symbol=>Object}] one entry of the devices snapshot
        # @return [Device, nil] nil for an entry without a device profile, such as +access_cards_count+
        def self.from(item)
          wrapper, body = item.first
          common = body&.dig(:common_device)
          profile = (common || body)&.dig(:profile)
          build(profile, **origin(common, wrapper), raw: item) if wrapper && profile
        end

        # @return [Array<Symbol>] the statuses whose message is +LightDeviceStatus.Simple+
        # @api private
        def self.flag_kinds
          status = 'systems.ajax.api.ecosystem.v3.mobilegwsvc.commonmodels.space.device.light.LightDeviceStatus'
          @flag_kinds ||= Schemas.pool.lookup(status).to_enum(:each).filter_map do |field|
            field.name.to_sym if field.subtype&.name == "#{status}.Simple"
          end
        end

        # @api private
        def self.origin(common, wrapper)
          return { kind: wrapper, hub_id: nil } unless common

          { kind: Decode.choice(common[:object_type]) || :unknown, hub_id: common[:hub_id].to_s }
        end

        # @api private
        def self.build(profile, kind:, hub_id:, raw:)
          new(id: profile[:id].to_s, name: profile[:name].to_s, kind:, hub_id:,
              room_id: profile[:room_id], group_id: profile[:group_id],
              states: (profile[:states] || []).map { Decode.enum(it, 'LIGHT_DEVICE_STATE_') },
              malfunctions: profile[:malfunctions].to_i, bypassed: profile[:bypassed] == true,
              **statuses(profile[:statuses] || []), raw:)
        end

        # @api private
        def self.statuses(list)
          found = list.reduce({}, :merge)
          { battery: found[:battery]&.then { Battery.from(it) },
            signal: found[:signal_strength]&.then { Decode.enum(it[:device_signal_level], 'DEVICE_SIGNAL_LEVEL_') },
            temperature: found[:temperature]&.then { it[:value].to_i }, flags: found.keys & flag_kinds }
        end
        private_class_method :origin, :build, :statuses
      end
    end
  end
end
