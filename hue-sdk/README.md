# hue-sdk

Unofficial Ruby SDK for the Philips Hue CLIP API v2. It talks to one bridge on the local
network, without any cloud service.

> **Unofficial.** This gem is not affiliated with, endorsed by or sponsored by Signify.
> Philips Hue is a trademark of Signify.

## Requirements

- Ruby 4.0 or later; no runtime dependency outside the standard library, except the `ffi` gem
  for Entertainment streaming.
- A Hue bridge speaking CLIP v2: Hue Bridge (v2) or Hue Bridge Pro.

## Installation

```ruby
# Gemfile
gem 'hue-sdk'
```

RBS signatures ship in `sig/`, so Steep checks code calling the SDK.

## Configuration

```ruby
require 'hue-sdk'

Hue::Sdk.configure do |config|
  config.host = '192.0.2.10'               # IP address or .local name of the bridge
  config.bridge_id = 'ECB5FAFFFE000001'    # checked against the bridge certificate
  config.application_key = ENV.fetch('HUE_APPLICATION_KEY')
end
```

| Setting | Default | Purpose |
|---|---|---|
| `host` | — | bridge address |
| `port` | `443` | HTTPS port |
| `bridge_id` | — | identity the bridge certificate must carry |
| `application_key` | — | key obtained by pairing |
| `client_key` | — | key obtained by pairing, used by Entertainment streaming |
| `ca_file` | embedded Signify root CA | CA the bridge certificate must chain to |
| `open_timeout` / `read_timeout` | `5` / `10` s | ordinary requests |
| `event_read_timeout` | `300` s | event stream |

Every connection is pinned: the bridge certificate must be signed by the Hue root CA and carry
the configured bridge id. Each thread, and each fiber within it, keeps its own keep-alive
connection.

## Discovery

Bridges announce themselves over mDNS (`_hue._tcp`). Discovery stays on the local network.

```ruby
bridge = Hue::Sdk.discover.first
bridge.host      # => "192.0.2.10"
bridge.bridge_id # => "ECB5FAFFFE000001"
bridge.model_id  # => "BSB003"
```

The query is sent again after 1 and 3 seconds, since Wi-Fi drops multicast packets; the default
4-second window fits three queries.

## Pairing

With `host` and `bridge_id` configured, from `discover` for instance, press the round button on
the bridge, then within 30 seconds:

```ruby
credentials = Hue::Sdk.pair(app_name: 'koti')
credentials.application_key
credentials.client_key
```

`Hue::Sdk::LinkButtonNotPressedError` means the button was not pressed in time. Store both keys
safely: the bridge shows them only once.

## Reading

Each resource type has an entry point named after it. Without an id it returns the collection;
with one, a single resource whose data loads on first access.

```ruby
Hue::Sdk.Light.list.each { |light| puts "#{light.owner['metadata']['name']}: #{light['on']['on']}" }

light = Hue::Sdk.Light('3f1a…')
light.data        # the whole resource
light['dimming']  # one attribute
```

`attributes` gives the same resource as a typed value, `Hue::Sdk::Schema::Light` for a light, its
nested objects typed too. Its signature tells which fields the bridge always sends; the others may
be `nil`.

```ruby
light.attributes.on.on                # => true
light.attributes.dimming&.brightness  # => 60.0, nil for a light that does not dim
```

`Hue::Sdk.resource(type, id = nil)` does the same from a type name. A type this version does not
know yet gets a read-only generic model instead of an error. Deprecated fields are left out of
`data` and of event changes: `effects` on a light, `device_mode` on a device, and the sensor
values superseded by a report (`motion.motion` by `motion.motion_report`, `button.last_event` by
`button.button_report`, and likewise for light level, temperature, bell and rotary).

## Writing

A resource only offers the operations the bridge accepts for its type.

```ruby
light.update(on: { on: true }, dimming: { brightness: 60.0 })

zone = Hue::Sdk.Zone.create(metadata: { name: 'Terrasse', archetype: 'terrace' },
                            children: [{ rid: light.id, rtype: 'light' }])
zone.delete
```

`update` returns the resource and reloads its data on next access; `create` returns the new
resource.

The changes can also be a typed request, of the class the Hue app sends for that type
(`Hue::Sdk::Schema::LightUpdate`, `Hue::Sdk::Schema::ZoneAdd`…): an unknown field, or one the
bridge needs left out or nil, raises `ArgumentError` before anything is sent.

```ruby
light.update(Hue::Sdk::Schema::LightUpdate.new(
  on: Hue::Sdk::Schema::OnFeatureUpdate.new(on: true),
  dimming: Hue::Sdk::Schema::DimmingFeatureUpdate.new(brightness: 60.0)
))
```

The app has request classes for 19 types to update and 8 to create, listed below. The hash form
remains for the other types, and keywords given along with a request are added to its body for the
fields the app never sends.

<details>
<summary>Resource types and operations</summary>

| Type | Entry point | Operations | Typed requests |
|---|---|---|---|
| `behavior_instance` | `Hue::Sdk.BehaviorInstance` | list, get, create, update, delete | — |
| `behavior_script` | `Hue::Sdk.BehaviorScript` | list, get, update | — |
| `behavior_script_formula` | `Hue::Sdk.BehaviorScriptFormula` | list, get, create, delete | — |
| `bell_button` | `Hue::Sdk.BellButton` | list, get, update | — |
| `bridge` | `Hue::Sdk.Bridge` | list, get, update | — |
| `bridge_home` | `Hue::Sdk.BridgeHome` | list, get | — |
| `button` | `Hue::Sdk.Button` | list, get, update | — |
| `camera_motion` | `Hue::Sdk.CameraMotion` | list, get, update | — |
| `clip` | `Hue::Sdk.Clip` | list, get | — |
| `contact` | `Hue::Sdk.Contact` | list, get, update | — |
| `convenience_area_motion` | `Hue::Sdk.ConvenienceAreaMotion` | list, get, update | `ConvenienceAreaMotionUpdate` |
| `device` | `Hue::Sdk.Device` | list, get, update, delete | `DeviceUpdate` |
| `device_power` | `Hue::Sdk.DevicePower` | list, get | — |
| `device_software_update` | `Hue::Sdk.DeviceSoftwareUpdate` | list, get, update | — |
| `entertainment` | `Hue::Sdk.Entertainment` | list, get, update | — |
| `entertainment_configuration` | `Hue::Sdk.EntertainmentConfiguration` | list, get, create, update, delete | `EntertainmentConfigurationUpdate`, `EntertainmentConfigurationAdd` |
| `geofence_client` | `Hue::Sdk.GeofenceClient` | list, get, create, update, delete | `GeofenceClientUpdate`, `GeofenceClientAdd` |
| `geolocation` | `Hue::Sdk.Geolocation` | list, get, update | — |
| `grouped_light` | `Hue::Sdk.GroupedLight` | list, get, update | `GroupedLightUpdate` |
| `grouped_light_level` | `Hue::Sdk.GroupedLightLevel` | list, get, update | — |
| `grouped_motion` | `Hue::Sdk.GroupedMotion` | list, get, update | — |
| `homekit` | `Hue::Sdk.Homekit` | list, get, update | — |
| `light` | `Hue::Sdk.Light` | list, get, update | `LightUpdate` |
| `light_level` | `Hue::Sdk.LightLevel` | list, get, update | — |
| `matter` | `Hue::Sdk.Matter` | list, get, update | — |
| `matter_fabric` | `Hue::Sdk.MatterFabric` | list, get, update, delete | — |
| `motion` | `Hue::Sdk.Motion` | list, get, update | `MotionUpdate` |
| `motion_area_candidate` | `Hue::Sdk.MotionAreaCandidate` | list, get, update | — |
| `motion_area_configuration` | `Hue::Sdk.MotionAreaConfiguration` | list, get, create, update, delete | `MotionAreaConfigurationUpdate`, `MotionAreaConfigurationAdd` |
| `power_output_configuration` | `Hue::Sdk.PowerOutputConfiguration` | list, get, update | `PowerOutputConfigurationUpdate` |
| `relative_rotary` | `Hue::Sdk.RelativeRotary` | list, get, update | — |
| `room` | `Hue::Sdk.Room` | list, get, create, update, delete | `RoomUpdate`, `RoomAdd` |
| `scene` | `Hue::Sdk.Scene` | list, get, create, update, delete | `SceneUpdate`, `SceneAdd` |
| `security_area_motion` | `Hue::Sdk.SecurityAreaMotion` | list, get, update | `SecurityAreaMotionUpdate` |
| `service_group` | `Hue::Sdk.ServiceGroup` | list, get, create, update, delete | `ServiceGroupUpdate`, `ServiceGroupAdd` |
| `smart_scene` | `Hue::Sdk.SmartScene` | list, get, create, update, delete | `SmartSceneUpdate`, `SmartSceneAdd` |
| `sonos` | `Hue::Sdk.Sonos` | list, get, update | `SonosUpdate` |
| `sonos_connectivity` | `Hue::Sdk.SonosConnectivity` | list, get | — |
| `speaker` | `Hue::Sdk.Speaker` | list, get, update | `SpeakerUpdate` |
| `switch_input_configuration` | `Hue::Sdk.SwitchInputConfiguration` | list, get, update | — |
| `tamper` | `Hue::Sdk.Tamper` | list, get, update | — |
| `temperature` | `Hue::Sdk.Temperature` | list, get, update | — |
| `wifi_connectivity` | `Hue::Sdk.WifiConnectivity` | list, get, update | — |
| `zgp_connectivity` | `Hue::Sdk.ZgpConnectivity` | list, get, update | — |
| `zigbee_connectivity` | `Hue::Sdk.ZigbeeConnectivity` | list, get, update | `ZigbeeConnectivityUpdate` |
| `zigbee_device_discovery` | `Hue::Sdk.ZigbeeDeviceDiscovery` | list, get, update | `ZigbeeDeviceDiscoveryUpdate` |
| `zone` | `Hue::Sdk.Zone` | list, get, create, update, delete | `ZoneUpdate`, `ZoneAdd` |

</details>

## Associations

References between resources resolve to resources of the right type:

```ruby
Hue::Sdk.Light('3f1a…').owner      # => the Device the light belongs to
Hue::Sdk.Room('8c2d…').children    # => the devices of the room
Hue::Sdk.Device('51b0…').services  # => its light, motion, battery… services
```

## Events

```ruby
Hue::Sdk.events do |event|
  next unless event.kind == :update && event.resource_type == 'light'

  puts "#{event.resource_id} changed: #{event.changes}"
end
```

`Hue::Sdk.events` blocks and yields a `Hue::Sdk::Event` per changed resource (`id`, `kind`,
`created_at`, `resource_type`, `resource_id`, `changes`, and `resource` to load it). Without a
block it returns a lazy enumerator.

The stream is read once: `events` returns when the bridge ends it, and raises
`Hue::Sdk::ConnectionError` when the bridge cannot be reached or drops it, as it does to a stream
idle for 5 minutes. Whether and when to follow the bridge again is the caller's. An
`Events::Stream` keeps the id of the last message whose events the block took whole, so a message
the block left part-way comes again. A stream opened with that id, or the same stream's `each`
called again, sends it as `Last-Event-ID`, and the bridge first sends the events of the gap: on
2026-11-01 it sent at once an event from a 2-minute gap.

```ruby
stream = Hue::Sdk::Events::Stream.new(last_event_id: previous&.last_event_id)
stream.each { |event| … }
```

A rejected application key raises `Hue::Sdk::AuthenticationError`, and an exception raised by the
block ends the stream and reaches the caller. The block may call the bridge: the stream has a
connection of its own.

## Entertainment streaming

Streaming drives the lights of an entertainment configuration (an entertainment area set up in
the Hue app) at up to 50 frames per second, over DTLS 1.2 with a pre-shared key: the application
key is the identity, the client key the secret.

```ruby
# Gemfile: gem 'ffi'
require 'hue/sdk/entertainment'

Hue::Sdk.configure { |config| config.client_key = ENV.fetch('HUE_CLIENT_KEY') }

Hue::Sdk.EntertainmentConfiguration('5c3e…').stream do |session|
  100.times do
    session.write({ 0 => [1.0, 0.0, 0.0], 1 => [0.0, 0.0, 1.0] })   # channel 0 red, channel 1 blue
    sleep 0.02
  end
end
```

`stream` starts the configuration, yields a session, then closes the connection, stops the
configuration and puts its lights back as they were before (on or off, brightness, color), even
when the block raises: the bridge itself leaves them on the last frame. A frame sets up to 20 channels, each value in
0.0..1.0; `color_space: :xy` takes x, y and brightness instead of red, green and blue.

Ruby's OpenSSL extension has no DTLS, so the SDK binds through `ffi` the libssl that extension
is linked with, wherever it is installed. Set `HUE_SDK_LIBSSL` to the path of another libssl
(OpenSSL 3 or 4) to use that one instead.

## Errors

| Error | Raised when |
|---|---|
| `Hue::Sdk::ConnectionError` | the bridge cannot be reached, or drops the connection |
| `Hue::Sdk::TLSError` | the bridge certificate fails the CA or bridge id check |
| `Hue::Sdk::AuthenticationError` | the application key is missing, unknown or revoked |
| `Hue::Sdk::LinkButtonNotPressedError` | pairing without pressing the link button |
| `Hue::Sdk::ResponseError` | the bridge answers with an error status, partial success (207) included; carries `status` and `errors` |
| `Hue::Sdk::NotFoundError` | the resource does not exist (a `ResponseError`) |
| `Hue::Sdk::RateLimitError` | the bridge asks to slow down (a `ResponseError`) |

All of them inherit from `Hue::Sdk::Error`.

## Sources

The resource types and the operations each one accepts were cross-checked between the types a
Bridge Pro firmware lists in its own `clip` resource, the
[openhue](https://github.com/openhue/openhue-api) OpenAPI description,
[aiohue](https://github.com/home-assistant-libs/aiohue) and
[Q42.HueApi](https://github.com/michielpost/Q42.HueApi).

The typed values come from the Hue app itself: the classes it parses the bridge's JSON with, and
the requests it sends. [schema/README.md](schema/README.md) tells how they were read and how to
regenerate them.

## Development

```sh
bundle install
bundle exec rake   # RuboCop, RSpec, YARD coverage, RBS validation, Steep
```

Live specs run against a real bridge and never write to it: any request other than `GET` is
refused.

```sh
HUE_LIVE=1 HUE_HOST=192.0.2.10 HUE_BRIDGE_ID=ECB5FAFFFE000001 HUE_APPLICATION_KEY=… \
  bundle exec rspec --tag live
```

## License

Mozilla Public License 2.0, see [LICENSE](LICENSE).
