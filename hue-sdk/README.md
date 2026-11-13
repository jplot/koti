# hue-sdk

Unofficial Ruby SDK for the Philips Hue CLIP API v2. It talks to one bridge on the local
network, without any cloud service. Only Hue Secure goes through the Hue account's cloud; it is loaded
apart.

> **Unofficial.** This gem is not affiliated with, endorsed by or sponsored by Signify.
> Philips Hue is a trademark of Signify.

## Requirements

- Ruby 4.0 or later; no runtime dependency outside the standard library, except the `ffi` gem
  for Entertainment streaming, the `grpc` gem to list the Hue Secure homes and the `mqtt` gem to follow one.
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

The app has request classes for 19 types to update and 8 to create, listed below with those of
`behavior_instance`, which it writes by hand. The hash form remains for the other types, and keywords
given along with a request are added to its body for the fields the app never sends.

<details>
<summary>Resource types and operations</summary>

| Type | Entry point | Operations | Typed requests |
|---|---|---|---|
| `behavior_instance` | `Hue::Sdk.BehaviorInstance` | list, get, create, update, delete | `BehaviorInstanceUpdate`, `BehaviorInstanceAdd` |
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

## Automations

A `behavior_instance` is an automation of the bridge: a wake-up, a timer, a schedule… Its configuration has a form per
script, which the bridge does not describe. `attributes` reads it with a class generated from the definitions of the Hue
app, and its state with `Hue::Sdk::Schema::BehaviorState`.

```ruby
automation = Hue::Sdk.BehaviorInstance('7b1f…').attributes
automation.configuration                       # => a Hue::Sdk::Schema::WakeUpConfiguration, for a wake-up
automation.configuration.when.time_point.time  # => #<data Hue::Sdk::Schema::TimeStamp hour=7, minute=0>
```

`Hue::Sdk::Schema::BEHAVIOR_SCRIPTS` gives the id of each script by a stable name: `coming_home`, `go_to_sleep`,
`leaving_home`, `native_go_to_sleep`, `pm_automation` (presence mimicking), `smoke_alarm`, `state_after_streaming`,
`time_based` (a schedule), `timer` and `wake_up`. The app does not know `native_go_to_sleep`, to which the bridge gives
the schema reference of `go_to_sleep`.

The configuration of an accessory is an automation too, under the script the app gives it:

| Script | Accessories |
|---|---|
| `hue_accessories` | switches, smart buttons, dimmers, the Hue Tap, motion sensors, doorbells, MotionAware areas; the Tap Dial on a bridge whose script supports it (`hue_tap_dial_switch`) |
| `tap_switch` | the Tap Dial otherwise |
| `motion_sensor` | cameras, despite its name, which is the bridge's |
| `contact_sensor` | contact sensors |

Any other script keeps its configuration as a hash, and so does a configuration its class would not send back whole, as
the app keeps what it cannot decode. `state` reads what the app reads. `data` always holds the JSON of the bridge, such as
the `source_type` of the state of a switch.

An `action` is a name (`all_off`, `home_off`, `dim_up`…), or a hash to recall a scene: `{ recall: { rid: '…', rtype: 'scene' } }`
to send one, and the same with string keys, as JSON, when read.

```ruby
switch = Hue::Sdk.BehaviorInstance('a91c…').attributes.configuration
switch.buttons.fetch('3e0f…').on_long_press.action  # => "home_off"
```

The configuration of an automation script keeps in `unknown` the keys its class does not know, and sends them back. As in
the app, a key its definition gives a default for may be missing, and the lights (`items`) of each scene of `what` are
written from those of the same group in `where`. The classes of accessories ignore the keys they do not know, as the app
does.

```ruby
schema = Hue::Sdk::Schema
room = schema::BehaviorGroup.new(rid: '8c2d…', rtype: 'room')
seven = schema::BehaviorTimePoint.new(type: 'time', time: schema::TimeStamp.new(hour: 7, minute: 0))

Hue::Sdk.BehaviorInstance.create(schema::BehaviorInstanceAdd.new(
  script_id: schema::BEHAVIOR_SCRIPTS.fetch(:wake_up),
  enabled: true,
  metadata: schema::BehaviorMetadata.new(name: 'Morning'),
  configuration: schema::WakeUpConfiguration.new(
    where: [schema::BehaviorGroupAndLights.new(group: room)],
    when: schema::BehaviorWhen.new(time_point: seven, recurrence_days: %w[monday friday]),
    fade_in_duration: schema::BehaviorFadeDuration.new(seconds: 1800)
  )
))

automation = Hue::Sdk.BehaviorInstance('7b1f…')
automation.update(schema::BehaviorInstanceUpdate.new(enabled: false))
automation.update(schema::BehaviorInstanceUpdate.new(trigger: schema::BehaviorTrigger.new(start: {}))) # stop: {} to stop
```

`BehaviorInstanceAdd` adds the types the app always names, `behavior_instance` and `instance_metadata`. The app builds
these requests by hand; their fields come from its code. Only `coming_home`, `go_to_sleep`, `hue_accessories`,
`leaving_home` and `time_based` were read on a real bridge, and the SDK never wrote an automation on one.

## Bridge settings

CLIP v2 only reports the time zone of the bridge. The Hue app reads it there, reads the other settings over CLIP v1 and
writes them all over CLIP v1, and so does `Hue::Sdk.settings`.

```ruby
settings = Hue::Sdk.settings
settings.time_zone          # => "Europe/Paris"
settings.software_version   # => "1970000000"

Hue::Sdk::Settings.time_zones                    # the time zones the bridge accepts
settings.update(time_zone: 'Europe/London')      # sends a request per setting, returns the values written
settings.update(utc: '2026-11-03T10:00:00')      # the clock of the bridge
settings.update(http_blocked: true)              # refuse plain HTTP
settings.update(analytics_consent: false)        # do not share statistics
```

`update` returns the settings with the values written, as the app keeps them. Only `http_blocked` is read back, as the
app does: it stays nil on a bridge that does not report it, and keeps its value if that read fails.

`remote_access` can only be read, as the app sets it when pairing. The network of the bridge and its software updates,
which the app also writes there, stay out of the SDK, and so do the application keys of other clients, which the same
answer holds. The SDK never wrote these settings on a real bridge.

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
block it returns a lazy enumerator. An error the bridge reports in the stream is an event of kind
`:error`, without a resource, whose `changes` hold its `errors`.

`attributes` gives the changes as a typed value without a request, `Hue::Sdk::Schema::LightChange`
for a light, as the app reads events. A field that did not change, or that the SDK hides as
deprecated, is nil, and a deleted resource only has its `id`. A type this version does not know gives
nil, and so do changes it cannot read, which stay in `changes`. The `configuration` of an automation
is typed when the event gives its script, as the event that adds one does; it stays a hash otherwise.

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

`stream` starts the configuration, yields a session, then closes the connection and stops the
configuration, even when the block raises. The bridge leaves the lights on the last frame. A frame
sets up to 20 channels, each value in 0.0..1.0; `color_space: :xy` takes x, y and brightness
instead of red, green and blue.

Ruby's OpenSSL extension has no DTLS, so the SDK binds through `ffi` the libssl that extension
is linked with, wherever it is installed. Set `HUE_SDK_LIBSSL` to the path of another libssl
(OpenSSL 3 or 4) to use that one instead.

## Hue Secure

> **Never tested with a Hue Secure device.** The requests follow the code of the Hue app; only the
> login, the renewal and the list of homes were tried, on an account without Hue Secure.

Hue Secure (arming, cameras and their events) lives in the Hue account's cloud, not on the
bridge. `require 'hue/sdk/secure'` loads it; `require 'hue/sdk'` does not.

The account logs in through Auth0 with the Hue app's client id. The gem does not ship that id:
the caller gives it as `client_id`. Logging in takes two steps, since the page ends on an address
only the app opens:

```ruby
require 'hue/sdk/secure'

Hue::Sdk::Secure.configure do |config|
  config.client_id = ENV.fetch('HUE_ACCOUNT_CLIENT_ID')
  config.token_file = 'hue-account.json'   # written in mode 0600
end

session = Hue::Sdk::Secure.session
puts session.authorize_url   # open it and log in
session.exchange(code)
```

Once logged in, the browser fails to open
`hue-auth0://auth.meethue.com/com.signify.hue/callback?code=…&state=…`; the developer tools of
the browser show that address, whose `code` goes to `exchange`. When the code comes back to
another process, keep `session.verifier` and pass it as `exchange(code, verifier:)`.

The token is saved in `token_file`, replaced whole in mode 0600, or given through `token` (from
`Token#to_json`). Auth0 rotates the refresh token on each renewal: the gem keeps `token` current,
for the caller to save it again, and a token file serves one process. The token is renewed 30 s
before it expires, once across threads: the threads that waited on a refused renewal raise its
`AuthenticationError`, and the saved token stays. No request is sent twice.

```ruby
# Gemfile: gem 'grpc'
Hue::Sdk::Secure.homes.map { |home| [home.name, home.security_activated] }

home = Hue::Sdk::Secure.home('5c3e…')   # by its id, without a request
Hue::Sdk::Secure.client.get("security/arm-manager/v1/home/#{home.id}/arm/state").body
```

The app lists the homes over gRPC: `homes` needs the `grpc` gem, nothing else does. `client`
reaches any path under `api_url`, or an absolute address, with the token, and gives the status,
the body (parsed when it is JSON) and the headers. The gem names itself in `User-Agent` and sends
none of the app's own headers.

| Setting | Default | Purpose |
|---|---|---|
| `client_id` | — | Auth0 client id of the Hue app |
| `token` / `token_file` | — | saved token; `token` is read first |
| `login_url` | `https://login.meethue.com` | OpenID discovery of the login |
| `api_url` | `https://api.account.meethue.com` | base of the paths given to `client` |
| `grpc_target` | `api.account.meethue.com:443` | gRPC service listing the homes |
| `auto_responses_url` | `https://automaticresponses.eu.secure.meethue.com` | the responses a doorbell may play |
| `mqtt_host` / `mqtt_port` | `mqtt.eu.secure.meethue.com` / `443` | the broker `follow` connects to |
| `mqtt_ca_file` | Amazon Root CA 1, embedded | the one root the broker's certificate must chain to |
| `grpc_credentials` | TLS with the system's roots | `:this_channel_is_insecure` for a test server |
| `open_timeout` / `read_timeout` | `5` / `10` s | each request |

### Arming

A home's arming, its schedules and the phones whose presence arms it follow the app's clients
(`ArmDisarmHttpClient`, `ArmDisarmScheduleHttpClient`, `CloudGeofenceHttpClient`):

```ruby
home = Hue::Sdk::Secure.homes.first
home.arm.read                       # => Schema::ArmDisarmResponse: state and configuration
home.arm.state&.arm_state           # => "armed_away"; state is nil for a home without Hue Secure
home.arm.set_state('armed_stay', delay: 30)
home.schedules.list                 # => [Schema::ArmDisarmScheduleResponse]
home.geofence.list                  # => [Schema::FetchGeofenceClientResponse]

week = Hue::Sdk::Secure::Schema::ArmDisarmScheduleConfigurationRequest.new(
  days: %w[monday friday],
  actions: [Hue::Sdk::Secure::Schema::ArmDisarmScheduleActionInfoRequest.new(time: '22:00', arm_state: 'armed_stay')]
)
home.schedules.create(Hue::Sdk::Secure::Schema::CreateArmDisarmScheduleRequest.new(name: 'Night', active: true,
                                                                                   schedules: [week]))
```

The answers and the requests are classes of `Hue::Sdk::Secure::Schema`, generated from the app's
own (see [schema/README.md](schema/README.md)). A request leaving a required field nil raises
`ArgumentError` before anything is sent. `arm.sound_alarm` sends the one body the app sends; when
part of the devices do not sound, the cloud answers 207 and the gem raises `ResponseError`.

### Cameras

The cameras of a home follow the app's `CamerasHttpClient`:

```ruby
camera = home.cameras.list.first
camera.attributes&.metadata&.name   # => "Front door"; attributes is nil for a camera the gem cannot read
camera.data                         # => the body the cloud reported, as it came
camera.update_motion(Hue::Sdk::Secure::Schema::CameraMotionSensitivityUpdate.new(sensitivity: 3))
camera.snapshot
camera.sound_chime(sound: 'ding_dong', volume: 0.6)   # volume from 0.0 to 1.0, or none
home.cameras.sound_group_alarm                        # the one group command the app sends

Hue::Sdk::Secure.auto_responses.categories   # the responses a doorbell may play
```

A camera also updates its camera, microphone, speaker and bell button services and its linked
devices, wakes up, reboots and resets. The siren of `sound_alarm` lasts the 10 s the app sends.
A camera out of reach answers 521, and a partial group 207: both raise `ResponseError`. The app
reads a camera it cannot decode as a wired camera; the gem keeps it with `attributes` nil and its
`data` whole.

### Timeline

The timeline of a home goes through the data API, as the app's `EventHttpClient` reaches it.
The gem reads one page at a time: going through the whole timeline is the caller's.

```ruby
range = { limit: 20, start_time: Time.now - 86_400, end_time: Time.now }
page = home.events.page(**range)
page.events.each { |message| p [message.type, message.event] }
page = home.events.page(**range, cursor: page.cursor) if page.cursor   # the same range; nil on the last page

home.events.last_significant   # the event the app shows first, or nil
home.events.all_safe(device_timestamp: Time.now)
```

Each event is read with the class the app chooses by its `type`, and for `clipv2`, `camera`,
`management` and `timeline` events by a key of the event itself. An event of a type the app does
not know, or of a shape the gem cannot read, keeps its JSON; the rest of the page still reads.
`events` also reads the insights of a phone (`insights`, whose id the caller gives), deletes,
reports and purges events, deletes a clip, and sends the alarm triggers.

### Following a home

`follow` connects to the MQTT broker of Hue Secure as the app does: TLS with ALPN `mqtt` to the one
root the app pins (Amazon Root CA 1), MQTT 3.1.1, the token in the username of AWS IoT's custom
authorizer, renewed when it expires within 30 s. It subscribes, never publishes, and yields each
message until the broker ends the connection; following it again is the caller's. It connects with the `mqtt` gem
from a thread of its own: it pings every 60 s and raises `ConnectionError` once 90 s pass without an answer, acknowledges
each message at the QoS 1 the app subscribes at as it hands it over, and sends DISCONNECT when the block stops. An
error the block raises goes through as it is, and the messages read before the broker ended the connection are still
yielded. Until njh/ruby-mqtt#171 is released, mqtt 0.7.0 holds a packet that shares a TLS record with the one before
it until the broker sends again, up to the next ping, and can then raise `ConnectionError` for a ping the broker did
answer; the fork below carries the fix.

```ruby
# Gemfile: gem 'mqtt', github: 'jplot/ruby-mqtt', branch: 'fix/ssl-buffered-packets'
home.follow do |message|
  message.topic        # => "arm/state"
  message.attributes   # => Schema::ArmDisarmStateResponse, or nil for a payload the gem cannot read
end
```

It follows `Follow::TOPICS` (`arm/state`, `arm/config`, `arm/schedules`, `device/+/config`,
`timeline/update`), or the `topics:` given. The gem names itself in its client id, rather than
the app's device and build.

## Errors

| Error | Raised when |
|---|---|
| `Hue::Sdk::ConnectionError` | the bridge or the Hue cloud cannot be reached, or drops the connection |
| `Hue::Sdk::TLSError` | the bridge certificate fails the CA or bridge id check; the broker of Hue Secure is not the pinned root's, or names another host |
| `Hue::Sdk::AuthenticationError` | the application key is missing, unknown or revoked; the Hue account has no token, or refuses it |
| `Hue::Sdk::LinkButtonNotPressedError` | pairing without pressing the link button |
| `Hue::Sdk::ResponseError` | the bridge or the Hue cloud answers with an error status, partial success (207) included; carries `status` and `errors` |
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

The live specs of Hue Secure read the account given by `HUE_ACCOUNT_CLIENT_ID` and
`HUE_ACCOUNT_TOKEN_FILE`, a token saved by the gem. They refuse any request other than `GET`,
except the renewal of the token.

## License

Mozilla Public License 2.0, see [LICENSE](LICENSE).
