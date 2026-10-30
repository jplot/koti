# ajax-sdk

Unofficial Ruby client for [Ajax Systems](https://ajax.systems) alarms. It receives the events your
hub sends over SIA DC-09 on the local network, and it logs in to the cloud the official mobile app
uses to read your spaces, devices and history, and to arm or disarm a space.

> **Unofficial.** Ajax Systems does not endorse or support this gem. "Ajax" and the Ajax logo are
> trademarks of Ajax Systems. Use it with an account you control, at your own risk.

## Requirements

ajax-sdk talks gRPC, so it depends on the `grpc` and `google-protobuf` gems, which ship precompiled
binaries up to **Ruby 3.4** — this gem targets Ruby 3.4 (the rest of koti stays on 4.0). TOTP codes
are computed with [`rotp`](https://github.com/mdp/rotp), and the SIA checksums with
[`digest-crc`](https://github.com/postmodern/digest-crc).

## Account

Use a **dedicated account** added to your space, not your personal one, with **two-factor
authentication** turned on. koti answers the 2FA challenge itself from the TOTP secret the app shows
when you enable it. The password is never stored: pass its lowercase SHA-256 hash, which is what the
app sends over the wire.

```ruby
require "ajax/sdk"

Ajax::Sdk.configure do |config|
  config.email          = ENV.fetch("AJAX_EMAIL")
  config.password_sha256 = ENV.fetch("AJAX_PASSWORD_SHA256") # or: config.password = ENV.fetch("AJAX_PASSWORD")
  config.totp_secret    = ENV.fetch("AJAX_TOTP_SECRET")
end
```

## Local events (SIA DC-09)

The hub can report its events straight to a monitoring station over SIA DC-09, without the cloud. In
the Ajax app, set the hub's monitoring station to SIA DC-09 with the address and port of the machine
running koti, an object number (the account) and an encryption key of 16 characters or 32 hexadecimal
digits (the hub encrypts with AES-128), then choose the SIA-DCS format:

```ruby
Ajax::Sdk.configure do |config|
  config.sia_account = ENV.fetch("AJAX_SIA_ACCOUNT")
  config.sia_key     = ENV.fetch("AJAX_SIA_KEY")
  config.sia_port    = 18_083 # the default; config.sia_host defaults to 0.0.0.0
end

Ajax::Sdk.sia_events do |event|
  event.code   # => "BA"
  event.label  # => "Burglary Alarm"
  event.group  # => "1"
  event.number # => "3", the device; for arming and disarming, the user
end

Ajax::Sdk.sia_events.first(3) # lazily, without a block; iterate it with each, first or take, not next
```

The receiver answers each frame the way DC-09 expects: an ACK (encrypted like the frame), a NAK when
the timestamp falls outside `config.sia_timeband` (40 s behind, 20 s ahead by default), a DUH for
another account or for a clear frame while a key is set, and nothing for a frame whose CRC or length
is wrong. SIA carries alarms, arming and disarming, and device troubles such as a low battery (`XT`)
or a lost connection (`XL`); it carries no battery percentage, no signal level and no commands. While
no receiver runs, the hub reports the monitoring station as lost. The ACK goes out as soon as an event
is queued, so events still queued when `sia_events` stops are lost to koti, though the hub counts them
as delivered.

Set a key. Without one, any device on the network can send events the receiver accepts. With one, a
device on the network cannot make up an event, but a device placed between the hub and koti can still
replay or alter frames: DC-09 encrypts without authenticating.

`Ajax::Sdk::Sia::Receiver` is the server itself, for running it under your own supervision; its block
may be called from several threads at once, one per hub connection, and an exception it raises is
reported with `warn` without closing the connection.

## Reading

```ruby
cloud = Ajax::Sdk.cloud

space = cloud.spaces.first
space.name           # => "Home"
space.security_state # => :disarmed
space.online         # => true

door = cloud.devices(space.id).find { it.kind == :door_protect_plus } # one snapshot
door.battery     # => #<data Battery state=:ok, charge=100, exact=true>
door.signal      # => :strong
door.temperature # => 22
door.states      # => [] ([:offline] when the hub lost it)
door.flags       # => [:armed_in_night_mode, :delay_when_leaving]

switch = cloud.devices(space.id).find { it.kind == :light_switch_two_gang }
switch.channels  # => [#<data Channel number=1, on=true, name="Hall", brightness=nil>, …]

note = cloud.notifications(space.id).first # most recent first
note.event       # => :space_disarmed
note.source      # => #<data Source type=:space_member, id="…", name="…">

cloud.notifications(space.id, older_than: note.token) # the page before it
cloud.notification_history(space.id).first(100)       # page after page
```

Spaces, devices and notifications come back as `Data` values (`Space`, `Device`, `Notification`, under
`Ajax::Sdk::Cloud`); their YARD and RBS signatures say which fields are always there and which may be
nil. A field the cloud leaves out reads as its protobuf default: an empty string, `0`, `false`, or
`:unspecified` for an enum. Each value keeps the whole decoded Hash in `raw`, for the statuses and
properties it does not name.

From its properties, a device also reads its `channels` (a relay's, a light switch's gangs, a socket's or a
valve's, with a dimmer's `brightness`; `on` is nil when the device does not know), a roller `shutter`
(`position` is the opening in percent, 100 open, nil while it moves), the state of a `lock` (`:locked`,
`:pending_unlocked`…), `life_quality` (temperature, humidity and CO2, whose units °C, % and ppm are inferred,
not verified) and a fire detector's `mute_command`. `space_id` names its space.

`notifications` reads one page, most recent first: 20 by default, the most the app asks for (the gateway's
own cap is unknown), with the notifications grouped under an offline one, whose `parent_id` names it.
`older_than:` or `newer_than:` take the `token` of a notification outside a group (`parent_id` nil), as the
app does, to read the page before or after it. `notification_history` reads every page lazily, each most
recent first, from the oldest notification outside a group of the page before; it stops on a page with
fewer than `limit` of them, so a gateway capping pages below `limit` ends it early. Grouped notifications
come with their group's page, which can put them after a newer page.

A battery whose `exact` is false comes from a device that reports no percentage: the app then shows
« OK » from 21 % and « discharged » below, not the number. `spaces` reads every page. A read the gateway
refuses raises `Ajax::Sdk::Cloud::ReadError`, whose `reason` names why (for example `:bad_request`).

## Following a space

```ruby
cloud.events(space.id) do |event|
  event.kind   # => :device
  event.key    # => [:hub_device, "0000ABCD", "0000BEEF"]
  event.before # => the Device before the change, nil when it appears
  event.after  # => the Device after it, nil when it goes
  event.state  # => #<data SpaceState space=…, security=…, groups={…}, rooms={…}, devices={…}>
end

cloud.events(space.id).first(10) # without a block: a lazy Enumerator
```

`events` follows one space through four streams of the gateway, each in its own thread: the space (its
security mode, groups and rooms), the account's spaces (the only source of the hub's online status), the
devices, and the notifications. The caller's thread alone applies their messages and yields one `Event` per
change:

| `kind` | `before` / `after` | `key` |
|---|---|---|
| `:space` | `Space` (name, security state, online) | the space id |
| `:security` | the generated `SpaceSecurityMode` | the space id |
| `:group`, `:room` | the generated `Group`, `Room` | their id |
| `:device` | `Device` | `[:hub_device, hub_id, device_id]` (the hub has `device_id == hub_id`), `[:video_edge, id]`, `[:video_edge_channel, video_edge_id, channel_id]`, `[:smart_lock, id]`, `[:chime, id]` |
| `:notification` | `Notification` | its id |

`state` is the whole space once the message that brought the change is applied. The first messages give every
item as an addition.

A stream that breaks (unavailable, deadline, internal, unauthenticated…) or ends reopens 1, 2, 4, 8, 16 then
30 seconds later, back to 1 second at its first message, forever. A snapshot after a reopening is compared
with what was kept, so the changes made meanwhile come out as events, and nothing else. The notification
stream has no snapshot: before it first opens, its thread notes the newest notification; before each
reopening, it reads back page by page the ones created since, waiting and retrying like the stream when that
read fails too. One created between that read and the reopening can be missed. A failure the gateway answers
(a refusal) is raised, and so is any other error. An exception in the block, `break`, or `first(n)` stops the
four threads and closes their calls; an Enumerator walked with `next` keeps them running. The queue between
the threads and the caller has no limit: a block slower than the streams makes it grow.

Not followed: the cloud smart locks' own stream, a roller shutter's movement, and the app's trouble, offline
and low-battery lists; their lasting state is already in the devices.

## Commanding

```ruby
cloud.arm(space.id)            # arm
cloud.arm(space.id, ignore_alarms: true)
cloud.disarm(space.id)         # disarm
cloud.arm_night(space.id)      # arm to night mode
cloud.disarm_night(space.id)   # disarm from night mode
```

A command the hub refuses raises `Ajax::Sdk::Cloud::CommandError`, whose `reason` names why
(for example `:hub_offline`). Set `config.read_only = true` to make every command raise
`Ajax::Sdk::Cloud::ReadOnlyError` before anything is sent — the live specs use it so they never change
a real alarm's state. The named and generic methods below obey it too: a method passes only when its gRPC
method (its service, for an `…/execute` path), which ends its Ruby name, starts with `get`, `find`,
`search` or `stream` and holds no write word (`create`, `delete`, `reset`, `test`…). So
`space_find_user_spaces_with_pagination` reads, and a stream that changes state is refused like any command.

## Shortcuts

| Shortcut | What it sends |
|---|---|
| `turn_on(device, channel: 1)`, `turn_off` | `device_command_device_on` / `_off`, with the family type the app sends: `light_switch`, `socket_base` or `water_stop_base` by the device's channels; `relay` with no channel, `relay_fibra_base` or `transmitter_fibra_base` by its kind |
| `set_brightness(device, percent)` | `device_command_brightness`: 1 to 100, relative, on the first channel |
| `open_shutter`, `close_shutter`, `stop_shutter(device)`, `move_shutter(device, percent)` | `device_command_roller_shutter_control`: the opening, 100 open and 0 closed, or stop |
| `bypass(device, tamper_only: false, once: false)`, `unbypass(device, once: false)` | `device_command_device_bypass` |
| `arm_group(space_id, group_id, ignore_alarms: false)`, `disarm_group` | `space_security_arm_group`, `space_security_disarm_group` |
| `set_security_mode(space_id, mode)` | `space_security_set_security_mode`: `:regular` or `:group` |
| `panic(space_id, location: nil)` | `space_press_panic_button`: **a real alarm** |
| `lock(device)`, `unlock`, `unlatch` | a lock of the hub: `device_command_device_off` / `_on`; a cloud lock: `switch_smart_lock`, the only one that unlatches |
| `mute(device)` | `device_command_sound_off`: the detector's own alarm, and external ones when its `mute_command` says so |
| `mute_fire_detectors(hub_id, except_triggered: false)` | `device_command_mute_all_fire_detectors` (`_except_triggered`) |
| `reset_fire_alarm(hub_id)` | `hub_command_en54_hub_action` |
| `device_details(device)`, `hub_details(space_id, hub_id)` | the first message of `stream_hub_device`, `stream_device_info`; a device whose type the app does not open this way (a hub, for example) raises `ReadError` `:refused` |
| `update_device_settings(device, *updates)`, `rename(device, name)`, `update_hub_settings(space_id, hub_id, *updates)` | `update_hub_device`, `update_device`; they return the success, which may say the change waits for a press on the device |
| `scenarios(space_id)`, `enable_scenario` / `disable_scenario(space_id, scenario_id)` | `stream_light_scenarios`, `set_scenario_state` |
| `rooms(space_id)`, `groups(space_id)` | the first message of `space_stream` |
| `life_quality_history(device, from:, to:, step: :hour, time_zone: 'UTC')` | `life_quality_data_get_life_quality_data`, as a `LifeQualityHistory`: each measure by the start of its bucket |

Each shortcut calls a named method (below), so Steep checks its request and read-only mode refuses its
commands. A device the shortcut does not fit raises `ArgumentError` before anything is sent; commands return
nil. They send what the app 3.59 sends, which differs from what one would guess in three places:

- The app never sends a slat command and never reads `SlatPosition`, so there is no slat shortcut.
- To turn a device on or off, it sends the type of its family, not the device's exact type. It always turns
  a legacy relay in impulse mode on; `turn_off` sends off to it anyway.
- `stream_hub_device` and `update_hub_device` do not cover relays, sockets, light switches or valves: their
  settings have no known path. A fire alarm resets through the cloud only on an EN54 hub.

Verified so far: the reads `rooms`, `hub_details` and `device_details`, against the real cloud and read-only;
`groups` answered an empty list. No shortcut that writes has been tried on a real device, and none has met a shutter, lock,
dimmer, valve, LifeQuality or EN54 device. The gateway refuses `scenarios` to an account whose role is a
plain user (`ReadError`, `:permission_denied`), as the live specs' account is.

## Any method

Every gRPC method the app has is in the shipped schema table, and the client has a method for each of
the 608, named after its path: the service without `Service`, then the method unless it is `execute`,
in snake_case.

```ruby
cloud.space_find_user_spaces_with_pagination(limit: 20) # SpaceService/findUserSpacesWithPagination
cloud.stream_light_devices(space_id: space.id).first     # StreamLightDevicesService/execute
```

A named method takes the fields of its request as keywords, with generated values for sub-messages; a
client stream or bidi method takes an Array of requests, each a generated value or a Hash as `#call`
takes it. It builds the request before anything is sent, streams included, so an unknown keyword or enum
symbol raises `ArgumentError` and a value of the wrong type (a Hash for a sub-message) `TypeError`. Its RBS
signature lets Steep reject a wrong keyword, a wrong type or an enum symbol the field does not have, and
types what comes back.

`#call` still reaches any method by its path:

```ruby
cloud.call("/systems.ajax.api.mobile.v2.space.SpaceService/findUserSpacesWithPagination")
```

`#call` picks the call kind (unary, server stream, …) from the table; `#unary`, `#server_stream`,
`#client_stream` and `#bidi` are the direct accessors. A request is a Hash, a generated value or a
google-protobuf message; a Hash names enum values as protobuf does (`:USER_ROLE_USER`), a value by
their short symbols (`:user`).

Responses come back as values generated from the app's schemas, under `Ajax::Sdk::Cloud::Messages`:
a `Data` class per message (5,828) and a module per enum (907), each loaded on its first use, with YARD
and RBS signatures that Steep checks.

- A message is a value whose members are its fields, plus `raw`, the Hash google-protobuf decoded;
  `to_message` gives the Hash back. A field the cloud leaves out holds its protobuf default (`0`, `''`,
  `false`, `[]`, `{}`); a sub-message, a oneof member or an `optional` field is nil instead.
- An enum value is a short symbol without the prefix its values share (`:ok` for `BATTERY_STATE_OK`,
  `:unspecified` for 0), or the number of a value the app 3.59 does not know.
- A oneof gives the name of the member that is set through a reader named after it.
- A `Timestamp` becomes a `Time` in UTC, a `Duration` a Float of seconds, a wrapper (`StringValue`…)
  what it holds.

A response whose `success` shares a oneof with its `failure` (or `error`), as 584 of the 608 methods
have, is unwrapped:
`call` returns the success, or raises `ReadError` for a read and `CommandError` for anything else. The
error's `reason` is the member of the failure that is set (`:hub_offline`), or `:refused` when the
answer holds neither member; `details` is what that member holds and `failure` the whole failure, so an
arming refused for `:hub_detected_malfunctions` carries the devices in trouble.

```ruby
page = cloud.call('/systems.ajax.api.mobile.v2.space.SpaceService/findUserSpacesWithPagination')
page.spaces.map { it.profile&.name }
```

A stream yields each message to the block, or returns an Enumerator without one; leaving it early
(`break`, `first`) closes the call. Streams have no deadline, every other call waits at most
`config.read_timeout` seconds (30 by default).

```ruby
path = '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service.stream_light_devices.StreamLightDevicesService/execute'
cloud.server_stream(path, { space_id: space.id }) { |message| … }
cloud.server_stream(path, { space_id: space.id }).first
```

## Errors

- `Cloud::AuthenticationError(reason)` — the login was refused (`:invalid_credentials`,
  `:account_locked`, `:invalid_totp`, …).
- `Cloud::CommandError(reason)` — the hub refused a command.
- `Cloud::ReadError(reason)` — the gateway refused a read.
  Both are `Cloud::RefusedError`s, with the `failure` the gateway answered and its `details`.
- `Cloud::ReadOnlyError` — a command was blocked because the client is read-only.
- `Cloud::UnknownMethodError` / `Cloud::UnknownMessageError` — an unknown path or message name.
- `Sia::FrameError` — a frame is not valid DC-09 (`Sia::Message.parse`); the receiver stays silent on it.
- `ConfigurationError` — a missing or malformed setting: no password, no `sia_account` for `sia_events`,
  a SIA key that is neither 16 characters nor 32 hexadecimal digits.

## Live specs

Read-only checks against the real cloud run with the account in the environment:

```sh
AJAX_LIVE=1 AJAX_EMAIL=… AJAX_PASSWORD_SHA256=… AJAX_TOTP_SECRET=… bundle exec rspec spec/live
```

They log in (with 2FA) and read spaces, devices and notifications; the client is read-only, so no
command reaches the hub.

## Sources

The protobuf schemas and the gRPC method table are extracted from the official Android app
(`com.ajaxsystems` 3.59) and shipped as `lib/ajax/sdk/cloud/schemas/`. Transport is the `grpc` gem,
messages are `google-protobuf`, TOTP is `rotp`. The SIA event labels in `lib/ajax/sdk/sia/codes.tsv`
come from [pysiaalarm](https://github.com/eavanvalkenburg/pysiaalarm) (MIT License, notice in
`LICENSE`). `schema/README.md` tells how to rebuild both.

## License

[Mozilla Public License 2.0](../LICENSE).
