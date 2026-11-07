# frozen_string_literal: true

require 'time'

module Hue
  module Sdk
    module Secure
      # One event of the timeline of a home.
      #
      # @!attribute [r] id
      #   @return [String, nil]
      # @!attribute [r] home_id
      #   @return [String, nil]
      # @!attribute [r] timestamp
      #   @return [String, nil]
      # @!attribute [r] type
      #   @return [String, nil] +action_all_safe+, +arm_state+, +camera+, +clipv2+, +trigger+, +timeline+, +management+
      #     or +geofence+
      # @!attribute [r] event
      #   @return [Sdk::Schema::Value, Object] the class the app reads it with, or the JSON of a type it does not
      #     know or a shape the gem cannot read
      # @!attribute [r] metadata
      #   @return [Schema::MessageEventMetaData, Object, nil]
      # @!attribute [r] trace_info
      #   @return [Schema::MessageEventTraceInfo, Object, nil]
      MessageEvent = Data.define(:id, :home_id, :timestamp, :type, :event, :metadata, :trace_info)

      # One event of the timeline, its +event+ read with the class the app chooses by its +type+
      # (+EventData._getEventDataFactory+), and for four types by a key of the event itself.
      class MessageEvent
        EVENTS = { 'action_all_safe' => :ActionAllSafeEvent, 'arm_state' => :ArmEvent, 'trigger' => :TriggerEvent,
                   'geofence' => :GeofenceEvent }.freeze
        private_constant :EVENTS

        KINDS = {
          'clipv2' => ['type', { 'motion' => :MotionClipV2Event, 'device_power' => :BatteryClipV2Event,
                                 'contact' => :ContactClipV2Event, 'tamper' => :TamperClipV2Event,
                                 'zigbee_connectivity' => :ZigbeeConnectivityClipV2Event,
                                 'security_area_motion' => :MotionAreaClipV2Event,
                                 'motion_area_configuration' => :MotionAreaConfigurationClipV2Event }],
          'camera' => ['resource_type', { 'security_motion_eventing' => :MotionCameraEvent,
                                          'camera_video_clips_eventing' => :ClipsUploadCameraEvent,
                                          'wifi_connectivity' => :WifiConnectivityCameraEvent,
                                          'device_power' => :BatteryCameraEvent,
                                          'audio_detection_eventing' => :AudioDetectionCameraEvent,
                                          'doorbell_button_event' => :DoorbellButtonCameraEvent }],
          'management' => ['type', { 'device_removed' => :DeviceRemovedEvent,
                                     'bridge_heartbeat' => :BridgeConnectivityEvent }],
          'timeline' => ['type', { 'delete_event_batch' => :DeleteTimelineEntriesEvent,
                                   'purge_timeline' => :PurgeTimelineEvent, 'refresh_timeline' => :RefreshTimelineEvent,
                                   'report_event_batch' => :ReportTimelineEntriesEvent }]
        }.freeze
        private_constant :KINDS

        # @param data [Hash{String=>Object}] one item of +data+
        # @return [MessageEvent]
        # @api public
        def self.from(data)
          new(id: data['id'], home_id: data['home_id'], timestamp: data['timestamp'], type: data['type'],
              event: typed(class_of(data['type'], data['event']), data['event']),
              metadata: typed(:MessageEventMetaData, data['metadata']),
              trace_info: typed(:MessageEventTraceInfo, data['trace_info']))
        end

        # @param type [String, nil]
        # @param event [Object]
        # @return [Symbol, nil] the name of the class in {Schema}
        # @api private
        def self.class_of(type, event)
          key, classes = KINDS[type.to_s]
          return EVENTS[type.to_s] unless key

          classes[event[key]] if event.is_a?(Hash)
        end

        # @param name [Symbol, nil]
        # @param data [Object]
        # @return [Object] the value, or +data+ as it came when no class reads it
        # @api private
        def self.typed(name, data)
          return data unless name && data.is_a?(Hash)

          Schema.const_get(name).from(data)
        rescue TypeError
          data
        end
      end

      # The timeline of a home and what acts on it, as the app's +EventHttpClient+ reaches them through the data API.
      # Never tested on a device.
      class Events
        # One page of the timeline.
        #
        # @!attribute [r] events
        #   @return [Array<MessageEvent>]
        # @!attribute [r] cursor
        #   @return [String, nil] what gives the next page, nil on the last one
        Page = Data.define(:events, :cursor)

        # @param home_id [String]
        # @api public
        def initialize(home_id)
          @home_id = home_id
          @path = "data/timeline/security/#{home_id}"
        end

        # Reads one page: going through the whole timeline is the caller's.
        #
        # @param limit [Integer]
        # @param start_time [Time, nil]
        # @param end_time [Time, nil]
        # @param cursor [String, nil] the {Page#cursor} of the page before
        # @return [Page]
        # @raise (see Http.request)
        # @api public
        def page(limit:, start_time: nil, end_time: nil, cursor: nil)
          query = { limit:, start_time: utc(start_time), end_time: utc(end_time) }.compact
          answer = Secure.client.get("#{@path}/range", query:, headers: cursor ? { 'x-cursor' => cursor } : {})
          next_cursor = answer.headers['x-cursor']
          Page.new(events: messages(answer.body), cursor: next_cursor.to_s.empty? ? nil : next_cursor)
        end

        # @return [MessageEvent, nil] the event the app shows first, nil when there is none
        # @raise (see Http.request)
        # @api public
        def last_significant = messages(Secure.client.get("#{@path}/significant-event").body).first

        # @param mobile_device_id [String] the phone the statistics are for, which the gem does not know
        # @param start_time [Time]
        # @param end_time [Time]
        # @return [Schema::SecurityEventInsightsResponse]
        # @raise (see Http.request)
        # @api public
        def insights(mobile_device_id, start_time:, end_time:)
          query = { start_time: utc(start_time), end_time: utc(end_time) }
          body = Secure.client.get("data/insights/security/#{@home_id}/mobile-devices/#{mobile_device_id}", query:).body
          Schema::SecurityEventInsightsResponse.from(body)
        end

        # @param request [Schema::TimelineEventsDelete]
        # @return [void]
        # @raise (see Http.request)
        # @api public
        def delete(request) = Secure.client.post("#{@path}/delete-events", body: request)

        # @param request [Schema::TimelineEventsReport]
        # @return [void]
        # @raise (see Http.request)
        # @api public
        def report(request) = Secure.client.put("#{@path}/report-events", body: request)

        # @return [void]
        # @raise (see Http.request)
        # @api public
        def purge = Secure.client.post("#{@path}/purge", body: {})

        # @param id [String]
        # @return [void]
        # @raise (see Http.request)
        # @api public
        def delete_clip(id) = Secure.client.delete("#{@path}/clips/#{id}")

        # @param device_timestamp [Time]
        # @return [void]
        # @raise (see Http.request)
        # @api public
        def all_safe(device_timestamp:)
          request = Schema::AllSafeRequest.new(home_id: @home_id, device_timestamp: utc(device_timestamp))
          Secure.client.post('data/resolve/all_safe', body: request)
        end

        # @param alarm_state [String] +alarm_started+, +alarm_stopped+ or +safety_alarm_stopped+
        # @param device_timestamp [Time]
        # @return [void]
        # @raise (see Http.request)
        # @api public
        def trigger_alarm(alarm_state, device_timestamp:)
          request = Schema::AlarmTriggerRequest.new(alarm_state:, device_timestamp: utc(device_timestamp))
          Secure.client.post("data/triggers/homes/#{@home_id}/alarm", body: request)
        end

        private

        # @param body [Hash{String=>Object}] a +DataApiResponse+
        # @return [Array<MessageEvent>]
        def messages(body) = body.fetch('data').compact.map { MessageEvent.from(it) }

        # @param time [Time, nil]
        # @return [String, nil]
        def utc(time) = time&.utc&.iso8601(3)
      end
    end
  end
end
