# frozen_string_literal: true

module Ajax
  module Sdk
    module Sia
      # A frame the receiver refused: the frame as it came, what the receiver answered (+:duh+, +:nak+, or nil
      # when it answered nothing) and why.
      Refusal = Data.define(:frame, :reply, :reason)
    end
  end
end
