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

      # A switchable output: a relay channel, a gang of a light switch, a socket or a valve. +on+ is nil
      # when the device does not know (a valve in +UNKNOWN+); +brightness+ is a dimmer's level in percent.
      Channel = Data.define(:number, :on, :name, :brightness) do
        # @param property [Data] a +LightHubDevice.SpreadProperties+ entry of a hub device
        # @return [Channel, nil] nil for a property that is not a channel
        def self.from(property)
          relay(property.channel) || gang(property.light_switch_channel) ||
            outlet(property.socket_base_channel || property.water_stop_channel)
        end

        # @api private
        def self.relay(relay)
          relay && new(number: relay.channel_id, on: relay.is_channel_on, name: relay.channel_name, brightness: nil)
        end

        # @api private
        def self.gang(gang)
          gang && new(number: number(gang.id), on: switched(gang.state), name: gang.name,
                      brightness: gang.brightness&.level)
        end

        # @api private
        def self.outlet(outlet)
          outlet && new(number: number(outlet.id), on: switched(outlet.state), name: nil, brightness: nil)
        end

        # +CHANNEL_ID_2+ reads as +:"2"+.
        #
        # @api private
        def self.number(id) = id.to_s.to_i

        # @api private
        def self.switched(state)
          case state
          when :on then true
          when :off then false
          end
        end
        private_class_method :relay, :gang, :outlet, :number, :switched
      end

      # A roller shutter: +position+ is its opening in percent (100 open, 0 closed), nil while it moves;
      # +moving+ is +:opening+ or +:closing+, nil at rest.
      Shutter = Data.define(:position, :moving) do
        # @param roller [Data] the +RollerPosition+ of a hub device
        # @return [Shutter]
        def self.from(roller) = new(position: roller.idle&.then { opening(it) }, moving: roller.moving&.direction)

        # @api private
        def self.opening(idle)
          case idle.idle_state
          when :fully_opened then 100
          when :fully_closed then 0
          else idle.partial_percent&.percent
          end
        end
        private_class_method :opening
      end

      # The LifeQuality measures, each nil when the device leaves it out; °C, % and ppm are inferred, not verified.
      LifeQuality = Data.define(:temperature, :humidity, :co2) do
        # @param info [Data] the +LifeQualityInfo+ of a hub device
        # @return [LifeQuality]
        def self.from(info)
          new(temperature: info.actual_temperature, humidity: info.actual_humidity, co2: info.actual_co2)
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
      # +channels+, +shutter+, +lock+ (+:locked+, +:pending_unlocked+…), +life_quality+ and +mute_command+
      # (+:own+ or +:own_plus_external+, what a fire detector's mute silences) come from its properties.
      Device = Data.define(:id, :name, :kind, :hub_id, :space_id, :room_id, :group_id, :states, :malfunctions,
                           :bypassed, :battery, :signal, :temperature, :flags, :channels, :shutter, :lock,
                           :life_quality, :mute_command, :raw) do
        # @param item [Data] one +LightDeviceItem+ of the devices snapshot
        # @param space_id [String] the space of the snapshot
        # @return [Device, nil] nil for an entry without a device profile, such as +access_cards_count+
        def self.from(item, space_id:)
          wrapper, body = item.raw.first
          common = body&.dig(:common_device)
          profile = (common || body)&.dig(:profile)
          return unless wrapper && profile

          build(profile, origin: origin(common, wrapper), space_id:, properties: properties(item), raw: item.raw)
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
        def self.build(profile, origin:, space_id:, properties:, raw:)
          new(id: profile[:id].to_s, name: profile[:name].to_s, **origin, space_id:,
              room_id: profile[:room_id], group_id: profile[:group_id],
              states: (profile[:states] || []).map { Decode.enum(it, 'LIGHT_DEVICE_STATE_') },
              malfunctions: profile[:malfunctions].to_i, bypassed: profile[:bypassed] == true,
              **statuses(profile[:statuses] || []), **properties, raw:)
        end

        # A cloud lock carries its state in its own properties, a lock of the hub among the hub device's.
        #
        # @api private
        def self.properties(item)
          spread = item.hub_device&.spread_properties || []
          { channels: spread.filter_map { Channel.from(it) }, shutter: shutter(spread),
            life_quality: life_quality(spread), lock: lock(item.smart_lock&.spread_properties || spread),
            mute_command: mute_command(spread) }
        end

        # @api private
        def self.shutter(spread) = spread.filter_map(&:roller_position).first&.then { Shutter.from(it) }

        # @api private
        def self.life_quality(spread) = spread.filter_map(&:life_quality_info).first&.then { LifeQuality.from(it) }

        # @api private
        def self.lock(spread) = spread.filter_map(&:smart_lock_control).first&.state

        # @api private
        def self.mute_command(spread)
          spread.filter_map { it.fire_device_action_button&.mute_button }.first&.mute_command
        end

        # @api private
        def self.statuses(list)
          found = list.reduce({}, :merge)
          { battery: found[:battery]&.then { Battery.from(it) },
            signal: found[:signal_strength]&.then { Decode.enum(it[:device_signal_level], 'DEVICE_SIGNAL_LEVEL_') },
            temperature: found[:temperature]&.then { it[:value].to_i }, flags: found.keys & flag_kinds }
        end
        private_class_method :origin, :build, :statuses, :properties, :shutter, :life_quality, :lock, :mute_command
      end
    end
  end
end
