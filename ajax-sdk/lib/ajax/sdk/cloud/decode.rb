# frozen_string_literal: true

module Ajax
  module Sdk
    module Cloud
      # Readers for the decoded Hashes. +to_h+ leaves out every field at its protobuf default (an enum
      # at 0, an empty string, +false+), so an absent enum reads as +:unspecified+.
      #
      # @api private
      module Decode
        module_function

        # @param value [Symbol, nil] an enum value, such as +:BATTERY_STATE_OK+
        # @param prefix [String] the prefix the enum repeats on every value
        # @return [Symbol] the value without its prefix, in lower case (+:ok+)
        def enum(value, prefix = '')
          name = value.to_s.delete_prefix(prefix).downcase
          name.empty? ? :unspecified : name.to_sym
        end

        # @param oneof [Hash{Symbol=>Object}, nil] a message holding one member of a oneof, such as +{ impulse: {} }+
        # @return [Symbol, nil] the member that is set
        def choice(oneof) = oneof&.keys&.first
      end
    end
  end
end
