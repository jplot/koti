# frozen_string_literal: true

module Ajax
  module Sdk
    module Sia
      # One event the hub reported over SIA: its account, its two-letter SIA code and label, the zone
      # (+ri+) and user (+id+) it names, its time, the rest of its data, and the {Message} it came in.
      # A content that does not read as SIA-DCS data keeps +code+ nil and lands whole in +text+.
      Event = Data.define(:account, :code, :label, :zone, :user, :time, :text, :raw)

      # Reading an event out of a message.
      class Event
        CONTENT = %r{
          \A(?:\#\h+\|)?N?(?:ti\d\d:\d\d/)?(?:id(?<user>\d*)/)?(?:ri(?<zone>\d*)/)?
          (?<code>[A-Z]{2})(?<text>.*)\z
        }xm
        private_constant :CONTENT

        # @param message [Message]
        # @return [Event]
        def self.from(message)
          fields = CONTENT.match(message.content.to_s)&.named_captures || { 'text' => message.content }
          new(account: message.account, code: fields['code'], label: Codes.label(fields['code'].to_s),
              zone: fields['zone'], user: fields['user'], time: message.timestamp, text: fields['text'], raw: message)
        end
      end
    end
  end
end
