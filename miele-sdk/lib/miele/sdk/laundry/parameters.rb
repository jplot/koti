# frozen_string_literal: true

module Miele
  module Sdk
    module Laundry
      # The app's DryingSteps flags.
      DRYING_LEVELS = { machine_iron: 1, hand_iron_plus: 2, hand_iron: 4, slightly_dry: 8, cupboard_dry: 16,
                        cupboard_dry_plus: 32, extra_dry: 64, deficiency_dry: 128, iron_dry: 256,
                        hygiene_dry: 512 }.freeze

      # What the app's laundry module writes as the parameters of a selected program. On DOP2 it reads 2/1577,
      # sets selection type 2, the program and the current values 2/1574 shows, then the parameters given; on Dop1
      # it reads 8201 or 8602 and writes it back. Each appliance class says which parameters it takes.
      module Parameters
        # @param settings [Hash{Symbol=>Object}] what the app writes, among +temperature+ (°C, with +eco+),
        #   +spin_speed+ (rpm), +soiling+, +cap+, +master_care+, +extras+ and +stains+ (names), +drying_level+ (a key
        #   of {DRYING_LEVELS}), +drying_time+ (minutes), +program_mode+ and +twin_dos+ (container values), as the
        #   appliance takes them. A Dop1 washer, as the app writes it, takes 0 for a temperature other than 20 to
        #   95 °C in steps of 5 (eco 40 or 60), and the TwinDos containers only when given both.
        # @return [void]
        # @raise [ActionUnavailableError] on an Opcode appliance, which has no selection object, or without a
        #   program on 2/1574
        # @raise [ArgumentError] for a parameter, extra, stain or drying level the SDK has no encoding for here, as
        #   the app writes none
        # @raise [NotAcceptedError] when a Dop1 appliance refuses them
        # @api public
        def set_parameters(**settings)
          require_selection!
          check_settings!(settings)
          return write_dop1_selection(dop1_parameters(read_dop1_selection, settings)) unless dop2?

          write_dop2_selection { |para, _| dop2_parameters(para, settings) }
        end

        # @return [Boolean] whether the app sets parameters: a program selected (Status 3) under mobile start, on
        #   DOP2 or Dop1
        # @api public
        def set_parameters_offered?
          state = self.state
          state.mobile_start? == true && status(state) == 3 && (protocol_version == 2 || dop2?)
        end

        private

        # @param settings [Hash{Symbol=>Object}]
        # @return [void]
        # @raise [ArgumentError]
        def check_settings!(settings)
          unknown = settings.keys - parameter_names
          unknown += setting_choices.flat_map { |name, choices| Array(settings[name]) - choices }
          raise ArgumentError, "#{unknown.join(', ')}: not written on this appliance" unless unknown.empty?
        end

        # SelectParametersAsync reads 2/1577, then 2/1574 once under a 10 s token of its own, then writes 2/1577.
        #
        # @yieldparam para [Data] the +selection_para+ with the appliance's current values
        # @yieldparam source [Data] its counterpart in 2/1574
        # @yieldreturn [Data] the one to write
        # @return [void]
        def write_dop2_selection
          modify(Objects::Laundry::GlobalPsSelect, [2, 1577, 0, 0]) do |select|
            context = Objects::Laundry::GlobalPsContext.from(dop2(2, 1574, idx1: 0, idx2: 1, timeout: 10).fields)
            select = with_appliance_values(select, context)
            select.with(para_member => yield(select.public_send(para_member), program_para(context)))
          end
        end

        # SetupPsSelectWithApplianceValues.
        #
        # @param select [Objects::Laundry::GlobalPsSelect]
        # @param context [Objects::Laundry::GlobalPsContext]
        # @return [Objects::Laundry::GlobalPsSelect]
        # @raise [ActionUnavailableError] without a program or the parameters of this kind of appliance
        def with_appliance_values(select, context)
          prog_id = context.prog_attributes_dwtdwm&.prog_id
          para = select.public_send(para_member)
          source = program_para(context)
          require!(!prog_id.nil? && para && source, 'the appliance shows no program to set')
          select.with(prog_id:, selection_type: 2, para_member => appliance_values(para, source))
        end

        # The SDK writes back only members 2/1577 carries.
        #
        # @param para [Data]
        # @param source [Data] its counterpart in 2/1574
        # @param map [Hash{Symbol=>Array(Symbol, Symbol)}] each member and where 2/1574 holds its value
        # @return [Data]
        def copied(para, source, map)
          values = map.to_h { |member, (from, field)| [member, source.public_send(from)&.public_send(field)] }
          para.with(**values.reject { |member, value| value.nil? || para.public_send(member).nil? })
        end

        # @param extras [Data, nil]
        # @param selected [Array<Symbol>]
        # @param names [Array<Symbol>] the extras the app writes, off unless selected; another selected is set on,
        #   each only where 2/1577 carries it
        # @return [Data]
        # @raise [ArgumentError] when 2/1577 carries no extras
        def chosen(extras, selected, names)
          raise ArgumentError, 'extras: 2/1577 carries none' if extras.nil?

          values = (names | selected).reject { extras.public_send(it).nil? }.to_h { [it, selected.include?(it)] }
          extras.with(**values)
        end
      end
    end
  end
end
