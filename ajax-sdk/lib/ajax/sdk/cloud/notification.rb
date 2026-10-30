# frozen_string_literal: true

module Ajax
  module Sdk
    module Cloud
      # Who or what raised a notification: +type+ is a device type (+:door_protect_plus+), +:user+,
      # +:space_member+, +:hub_2_4g+…
      Source = Data.define(:type, :id, :name) do
        # @param raw [Hash{Symbol=>Object}] the source of a notification content
        # @return [Source]
        def self.from(raw) = new(type: Decode.enum(raw[:type]), id: raw[:id].to_s, name: raw[:name])
      end

      # One entry of a space's history.
      #
      # +kind+ is where it comes from: +:hub+, +:space+, +:video+, +:smart_lock+, +:company+,
      # +:accounting+ or +:blank+. +event+ names what happened (+:motion_detected+, +:space_disarmed+…)
      # and +transition+ how (+:triggered+, +:recovered+ or +:impulse+). +folder+ is the app's tab
      # (+:alarm+, +:malfunction+, +:user_automation+…) and +importance+ +:default+, +:positive+,
      # +:warning+ or +:attention+. +token+ is its universal token, which reads the pages around it.
      # +parent_id+ is the offline notification it is grouped under, nil outside a group.
      Notification = Data.define(:id, :time, :kind, :event, :transition, :source, :folder, :importance, :read,
                                 :token, :parent_id, :raw) do
        # @param raw [Hash{Symbol=>Object}] one entry of findNotifications
        # @param parent_id [String, nil] the offline notification it is grouped under
        # @return [Notification]
        def self.from(raw, parent_id: nil)
          kind, content = raw[:content]&.first
          new(id: raw[:id].to_s, time: Decode.time(raw[:server_timestamp]),
              kind: kind ? kind.to_s.delete_suffix('_notification_content').to_sym : :unknown, **about(content || {}),
              **marks(raw), parent_id:, raw:)
        end

        # @api private
        def self.marks(raw)
          { folder: Decode.enum(raw[:folder], 'FOLDER_'), importance: Decode.enum(raw[:importance], 'IMPORTANCE_'),
            read: raw[:read_by_user] == true, token: raw[:universal_token].to_s }
        end

        # @api private
        def self.about(content)
          qualifier = content[:qualifier] || {}
          source = content[:source] || content[:space_source] || content[:hub_source]
          { event: Decode.choice(qualifier[:tag]), transition: Decode.choice(qualifier[:transition]),
            source: source&.then { Source.from(it) } }
        end
        private_class_method :about, :marks
      end
    end
  end
end
