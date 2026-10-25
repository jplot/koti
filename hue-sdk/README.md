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
the configured bridge id. Each thread keeps its own keep-alive connection.

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

Press the round button on the bridge, then within 30 seconds:

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
Hue::Sdk.Light.list.each { |light| puts "#{light['metadata']['name']}: #{light['on']['on']}" }

light = Hue::Sdk.Light('3f1a…')
light.data        # the whole resource
light['dimming']  # one attribute
```

`Hue::Sdk.resource(type, id = nil)` does the same from a type name. A type this version does not
know yet gets a read-only generic model instead of an error. Deprecated fields (`effects` on a
light, `device_mode` on a device) are left out of `data`.

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

<details>
<summary>Resource types and operations</summary>

| Type | Entry point | Operations |
|---|---|---|
| `behavior_instance` | `Hue::Sdk.BehaviorInstance` | list, get, create, update, delete |
| `behavior_script` | `Hue::Sdk.BehaviorScript` | list, get, update |
| `behavior_script_formula` | `Hue::Sdk.BehaviorScriptFormula` | list, get, create, delete |
| `bell_button` | `Hue::Sdk.BellButton` | list, get, update |
| `bridge` | `Hue::Sdk.Bridge` | list, get, update |
| `bridge_home` | `Hue::Sdk.BridgeHome` | list, get |
| `button` | `Hue::Sdk.Button` | list, get, update |
| `camera_motion` | `Hue::Sdk.CameraMotion` | list, get, update |
| `clip` | `Hue::Sdk.Clip` | list, get |
| `contact` | `Hue::Sdk.Contact` | list, get, update |
| `convenience_area_motion` | `Hue::Sdk.ConvenienceAreaMotion` | list, get, update |
| `device` | `Hue::Sdk.Device` | list, get, update, delete |
| `device_power` | `Hue::Sdk.DevicePower` | list, get |
| `device_software_update` | `Hue::Sdk.DeviceSoftwareUpdate` | list, get, update |
| `entertainment` | `Hue::Sdk.Entertainment` | list, get, update |
| `entertainment_configuration` | `Hue::Sdk.EntertainmentConfiguration` | list, get, create, update, delete |
| `geofence_client` | `Hue::Sdk.GeofenceClient` | list, get, create, update, delete |
| `geolocation` | `Hue::Sdk.Geolocation` | list, get, update |
| `grouped_light` | `Hue::Sdk.GroupedLight` | list, get, update |
| `grouped_light_level` | `Hue::Sdk.GroupedLightLevel` | list, get, update |
| `grouped_motion` | `Hue::Sdk.GroupedMotion` | list, get, update |
| `homekit` | `Hue::Sdk.Homekit` | list, get, update |
| `light` | `Hue::Sdk.Light` | list, get, update |
| `light_level` | `Hue::Sdk.LightLevel` | list, get, update |
| `matter` | `Hue::Sdk.Matter` | list, get, update |
| `matter_fabric` | `Hue::Sdk.MatterFabric` | list, get, update, delete |
| `motion` | `Hue::Sdk.Motion` | list, get, update |
| `motion_area_candidate` | `Hue::Sdk.MotionAreaCandidate` | list, get, update |
| `motion_area_configuration` | `Hue::Sdk.MotionAreaConfiguration` | list, get, create, update, delete |
| `power_output_configuration` | `Hue::Sdk.PowerOutputConfiguration` | list, get, update |
| `relative_rotary` | `Hue::Sdk.RelativeRotary` | list, get, update |
| `room` | `Hue::Sdk.Room` | list, get, create, update, delete |
| `scene` | `Hue::Sdk.Scene` | list, get, create, update, delete |
| `security_area_motion` | `Hue::Sdk.SecurityAreaMotion` | list, get, update |
| `service_group` | `Hue::Sdk.ServiceGroup` | list, get, create, update, delete |
| `smart_scene` | `Hue::Sdk.SmartScene` | list, get, create, update, delete |
| `speaker` | `Hue::Sdk.Speaker` | list, get, update |
| `switch_input_configuration` | `Hue::Sdk.SwitchInputConfiguration` | list, get, update |
| `tamper` | `Hue::Sdk.Tamper` | list, get, update |
| `temperature` | `Hue::Sdk.Temperature` | list, get, update |
| `wifi_connectivity` | `Hue::Sdk.WifiConnectivity` | list, get, update |
| `zgp_connectivity` | `Hue::Sdk.ZgpConnectivity` | list, get, update |
| `zigbee_connectivity` | `Hue::Sdk.ZigbeeConnectivity` | list, get, update |
| `zigbee_device_discovery` | `Hue::Sdk.ZigbeeDeviceDiscovery` | list, get, update |
| `zone` | `Hue::Sdk.Zone` | list, get, create, update, delete |

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

The stream reconnects by itself when it breaks — the bridge closes an idle stream after
5 minutes — waiting 1, 2, 4, 8, 16 then 30 seconds, and resumes from the last event received.
A rejected application key raises `Hue::Sdk::AuthenticationError` instead of reconnecting.
The block may call the bridge: the stream has a connection of its own.

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
    session.write({ 0 => [1.0, 0.0, 0.0], 1 => [0.0, 0.0, 1.0] })   # red, green, blue per channel
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
[aiohue](https://github.com/home-assistant-libs/aiohue),
[Q42.HueApi](https://github.com/michielpost/Q42.HueApi) and the official Hue app 6.3.2.

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

Mozilla Public License 2.0, see [LICENSE](../LICENSE).
