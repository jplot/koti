# frozen_string_literal: true

require 'json'

module Miele
  module Sdk
    module Cloud
      # The fields of a CIAM answer, read as the app's WebExDecoder reads them: JSON when the body holds braces or
      # brackets and parses as an object, else a form, after a leading # or ?.
      module WebExDecoder
        module_function

        # @param body [String]
        # @return [Hash{String=>Object}]
        # @api private
        def decode(body) = object(body) || form(body)

        # @param body [String]
        # @return [Hash{String=>Object}, nil]
        # @api private
        def object(body)
          return unless %w[{ }].all? { body.include?(it) } || %w{[ ]}.all? { body.include?(it) }

          parsed = JSON.parse(body, allow_trailing_comma: true)
          parsed if parsed.is_a?(Hash)
        rescue JSON::ParserError
          nil
        end

        # @param body [String]
        # @return [Hash{String=>String}]
        # @api private
        def form(body)
          body.sub(/\A[#?]/, '').split('&').reject(&:empty?).to_h do |pair|
            key, value = pair.split('=', 2)
            [unescape(key.to_s), unescape(value.to_s)]
          end
        end

        # Uri.UnescapeDataString leaves a + and a malformed escape as they are.
        #
        # @param text [String]
        # @return [String]
        # @api private
        def unescape(text) = text.b.gsub(/%\h\h/) { [it.delete_prefix('%')].pack('H2') }.force_encoding(Encoding::UTF_8)
      end
    end
  end
end
