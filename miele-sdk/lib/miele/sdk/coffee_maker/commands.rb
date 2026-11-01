# frozen_string_literal: true

module Miele
  module Sdk
    class CoffeeMaker < Appliance
      # Power, light, stop and acknowledgements as the app's coffee module sends them: a DOP2 coffee maker takes
      # 2/1586 as read, and its other objects through ModifyDop2Message; a CVA6000 takes Dop1 1101 and 1100, and
      # its light in +State+, after the checks of the app's dashboard.
      module Commands
        # The notification member each type acknowledges with its id; the others take their option only.
        MESSAGE_TYPES = { information: :info, message: nil, query: :query, warning: nil, error: nil }.freeze
        # The CVA6000 statuses the app's light and switch-off actions take.
        LIGHT_STATUSES = [1, 2, 3, 5, 6, 7, 8, 9, 144, 147].freeze
        SWITCH_OFF_STATUSES = [2, 3, 6, 7, 8, 9].freeze
        private_constant :MESSAGE_TYPES, :LIGHT_STATUSES, :SWITCH_OFF_STATUSES

        # A sleeping DOP2 coffee maker answers 500: the app wakes it (+DeviceAction+ 2), waits 5 s and reads
        # 2/1586 again, then waits 1.5 s before it writes it.
        #
        # @return [void]
        # @raise [ActionUnavailableError] unless off (Status 1) under remote control without local control, a
        #   known variant on DOP2, as the app's power switch allows it
        # @api public
        def power_on
          state = self.state
          return write_device_action(2) if dop1_switch?(state, [1])

          require!(variant != :unknown && switchable?(state, [1]), 'the coffee maker cannot be switched on now')
          combi = read_combi_state
          return if family::GlobalEnumApplianceState.to_i(combi.appliance_state) == 4

          @sleeper.call(1.5)
          write_object(combi.with(appliance_state: 4), [2, 1586, 0, 0])
        end

        # @return [void]
        # @raise [ActionUnavailableError] unless on (Status 2 or 3) under remote control without local control and
        #   no Barista running, as the app's power switch allows it; on a CVA6000, unless on, paused, ended, failed
        #   or cancelled
        # @api public
        def power_off
          state = self.state
          return write_device_action(3) if dop1_switch?(state, SWITCH_OFF_STATUSES)

          require!(switchable?(state, [2, 3]) && program_id != Brewing::BARISTA,
                   'the coffee maker cannot be switched off now')
          modify(family::GlobalDeviceCombiState, [2, 1586, 0, 0]) { it.with(appliance_state: 1) }
        end

        # The app writes back the whole +State+ it read, the light changed.
        #
        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] but on a CVA6000 neither disconnected, locked nor in service
        # @api public
        def light=(on)
          state = self.state
          require!(dop1_switch?(state, LIGHT_STATUSES), 'the app switches the light of a CVA6000 only')
          command(Schema::DeviceState.from(state.raw).with(light: on ? 1 : 2))
        end

        # @return [void]
        # @raise [ActionUnavailableError] on a CVA6000 that runs no drink
        # @api public
        def stop
          return modify_dop2(family::GlobalUserReqRequest, 2, 1583, 0, 1) { it.with(request: 2) } if dop2?

          require!(dop1_switch?(state, [5]), 'the coffee maker runs no drink to stop')
          klass = Objects::CoffeeGen7::ProcessActionCva
          section = blank(klass::ProcessActionWriteSection).with(struktur_version: 1, action: 2)
          write_dop1_object(klass, section, type: Dop1::WRITE)
        end

        # @param type [Symbol] +:information+, +:message+, +:query+, +:warning+ or +:error+
        # @param id [Integer, Symbol, nil] an information's or a query's id
        # @param option [Integer, Symbol]
        # @return [void]
        # @raise [ActionUnavailableError] on a CVA6000, where the app acknowledges nothing
        # @raise [ArgumentError] for an option outside 1 to 17, or 1 to 16 on a CM7
        # @api public
        def acknowledge(type, id = nil, option:)
          member = MESSAGE_TYPES.fetch(type) { raise ArgumentError, "no #{type} notification" }
          require!(dop2?, 'the app acknowledges nothing on a CVA6000')
          require_option!(option)
          modify_dop2(family::GlobalNtfctnAcknowledge, 2, 138, 0, 1) do |ack|
            member ? ack.with(member => id, ack_option: option) : ack.with(ack_option: option)
          end
        end

        private

        # The app's acknowledge mappers throw outside 1 to 17, 1 to 16 on a CM7, before anything is read.
        #
        # @param option [Integer, Symbol]
        # @return [void]
        # @raise [ArgumentError]
        def require_option!(option)
          last = variant == :cm7 ? 16 : 17
          return if (1..last).cover?(family::GlobalEnumNTFCTNAckOptions.to_i(option))

          raise ArgumentError, "no acknowledge option #{option}"
        end

        # @return [Data] 2/1586 at 0/0
        def read_combi_state
          object(family::GlobalDeviceCombiState, [2, 1586, 0, 0])
        rescue ResponseError => e
          raise unless e.status == 500

          wake
          @sleeper.call(5)
          object(family::GlobalDeviceCombiState, [2, 1586, 0, 0])
        end

        # @param state [State]
        # @param statuses [Array<Integer>] off (1) to switch on, on (2 and 3) to switch off
        # @return [Boolean] in one of them, under remote control without local control
        def switchable?(state, statuses)
          statuses.include?(status(state)) && state.remote_control? == true && state.local_control? != true
        end

        # @param state [State]
        # @param statuses [Array<Integer>] those the action takes
        # @return [Boolean] a Dop1 coffee maker in one of them under the CVA6000's remote control
        # @raise [ActionUnavailableError] on a Dop1 coffee maker in another status
        def dop1_switch?(state, statuses)
          return false unless protocol_version == 2

          remote = ![0, 8].include?(state.raw.dig('RemoteEnable', 0).to_i) || [12, 145].include?(status(state))
          require!(statuses.include?(status(state)) && remote, 'the coffee maker cannot do that now')
          true
        end

        # @param state [State]
        # @return [Integer]
        def status(state) = state.raw['Status'].to_i

        # @return [Integer] the +ProgId+ of the program context, 0 without one
        def program_id
          id = program_context&.prog_attributes_cca&.prog_id
          id.nil? ? 0 : family::GlobalEnumPrgId.to_i(id)
        end

        # @param action [Integer] 2 on, 3 off
        # @return [void]
        def write_device_action(action)
          klass = Objects::CoffeeGen7::DeviceAction
          section = blank(klass::DeviceActionWriteSection).with(struktur_version: 1, action:)
          write_dop1_object(klass, section, type: Dop1::WRITE)
        end

        # ModifyDop2ObjectAsync: the app writes back where it read, with idx1 as the header's attribute and as
        # both indexes of an instance read above 0.
        #
        # @param klass [Class] a generated DOP2 class
        # @param unit [Integer]
        # @param attribute [Integer]
        # @param idx1 [Integer]
        # @param idx2 [Integer]
        # @yieldparam value [Data] the object as read
        # @yieldreturn [Data] the object to write
        # @return [void]
        def modify_dop2(klass, unit, attribute, idx1, idx2)
          leaf = dop2(unit, attribute, idx1:, idx2:)
          fields = yield(klass.from(leaf.fields)).to_fields
          leaf = leaf.with(idx1:, idx2: idx1) if leaf.idx1.positive?
          body = Dop2.encode(leaf.with(attribute: idx1, fields:))
          send_request(:put, "#{dop2_path(unit, attribute)}?idx1=#{idx1}&idx2=#{idx2}", body:, kind: :dop2)
        end
      end
    end
  end
end
