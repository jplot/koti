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
| `rooms(space_id)`, `groups(space_id)`, `current_member(space_id)` | the first message of `space_stream` |
| `life_quality_history(device, from:, to:, step: :hour, time_zone: 'UTC')` | `life_quality_data_get_life_quality_data`, as a `LifeQualityHistory`: each measure by the start of its bucket |
| `take_photo(device)` | `photo_on_demand_capture_photo`, with the camera's family as the app names it: `:cam`, `:cam_outdoor` or `:cam_fibra_base` |
| `notification_media(space_id, notification_id)` | `notification_log_stream_notification_media`: each state of the notification's media, as an `Enumerator::Lazy` |

Each shortcut calls a named method (below), so Steep checks its request and read-only mode refuses its
commands. A device the shortcut does not fit raises `ArgumentError` before anything is sent; commands return
nil. They send what the app 3.59 sends, which differs from what one would guess in three places:

- The app never sends a slat command and never reads `SlatPosition`, so there is no slat shortcut.
- To turn a device on or off, it sends the type of its family, not the device's exact type. It always turns
  a legacy relay in impulse mode on; `turn_off` sends off to it anyway.
- `stream_hub_device` and `update_hub_device` do not cover relays, sockets, light switches or valves: their
  settings have no known path. A fire alarm resets through the cloud only on an EN54 hub.

Verified so far: the reads `rooms`, `current_member`, `hub_details`, `device_details` and `notification_media`, against the real
cloud and read-only; `groups` answered an empty list. No shortcut that writes has been tried on a real device,
and none has met a shutter, lock, dimmer, valve, LifeQuality or EN54 device. The gateway refuses `scenarios`
to the live specs' account (`ReadError`, `:permission_denied`), which has neither `scenario_edit` nor wide
`manage_automation_scenarios`: the app would not offer it either.

### Photos

A MotionCam takes photos on demand, when it detects motion while armed, and by scenario or schedule. They
come as a notification whose `image_resource` lists them by status, and `notification_media` gives their
addresses once they are ready. The app opens photos on `:motion_detected`, `:photo_on_demand…`,
`:photo_by_scenario…`, `:photo_by_schedule` and `:photo_on_demand_for_detection_area` notifications, and on
some models on `:tamper_opened`, `:masking_detected`, `:ice_detected` or `:device_moved` ones:

```ruby
cloud.take_photo(camera) # the app's photo on demand button; nothing comes back
note = cloud.notifications(space.id).find(&:image_resource)
ready = cloud.notification_media(space.id, note.id).find do |media|
  media.hub_notification_media&.images&.none? { it.status == :in_progress }
end
ready.hub_notification_media.images.select { it.status == :ready }.map(&:url) # pre-signed: shown as they are
```

A request gives 1 to 5 photos and an alarm 0 to 5, as the camera's settings say; the app shows the ready ones
and plays a series at 500 ms a photo. The links carry their signature and expire (`X-Amz-Expires`), so read them when they are needed; once
the media itself has expired, `notification_media` raises `ReadError` `:media_expired`. An archive export
comes the same way, as `archive_export_media`.

## Permissions

`current_member(space_id)` gives the signed-in account as a member of the space: the `CurrentMember` the
app reads to offer only what the account may do. A plain user or an admin is its `user_current_member`:

```ruby
me = cloud.current_member(space.id).user_current_member
me.role                          # => :user
me.space_permissions.permissions # => [:arm, :disarm, :structure_visibility, ...]
me.devices_permissions.filter_map(&:hub_permissions).first&.hub_permissions # => [:set_state_commands, ...]
```

The app 3.59 checks these in the screen, menu item or button that offers an action, then sends without
checking again; the SDK does not check them either and leaves the answer to the gateway, whose refusal is a
`CommandError` or `ReadError` with `:permission_denied`. Whether it refuses what the app would not offer is
known only for `scenarios`. What the app checks, read on the screen that offers each action (other ways in
were not all followed):

| Action | What the app checks |
|---|---|
| `arm`, `disarm`, `arm_night`, `disarm_night` | nothing: it never reads `arm` or `night_mode_arm_disarm` |
| `arm_group`, `disarm_group` | the group's `group_permissions` entry is `:enabled`; it lists no other group |
| `set_security_mode` | space `groups_edit`; the space disarmed, the hub online and not busy |
| `panic` | space `panic_button` |
| `turn_on`, `turn_off`, `set_brightness` | hub `set_state_commands`; the device online and not bypassed |
| the shutter shortcuts | nothing |
| `bypass`, `unbypass` | space `device_edit`; the hub online, the space disarmed. A device that does not report to the monitoring station, with the wide feature on: also wide `manage_non_monitored_devices`, the device online, armed or not. With `once: true`: hub `one_time_bypass` (or `device_edit`, by an app feature flag), the hub online, the space disarmed; while arming with malfunctions, `one_time_bypass` alone |
| `lock`, `unlock`, `unlatch` | the lock's own entry, permanent or not yet expired: `manage_lock` in `smart_lock_permissions` (a cloud lock), `manage_smart_lock` in `hub_device_user_privacy_permissions` (a lock of the hub) |
| `mute` | each item the detector's mute button lists in `required_permissions`: `:groups`, its group `:enabled`; `:mute`, hub `mute_fire_protect`; `:home_automation`, hub `set_state_commands`. An account with no entry for the hub passes the last two |
| `mute_fire_detectors` | role `:admin`, or hub `mute_fire_protect` unless the account is a plain user and the hub's apartment mode is on |
| `reset_fire_alarm` | the reset button `stream_fire_control` sends is enabled; at access level 2, also hub `en54_access_level_2` (`hub_permissions_extended`) |
| `rename` | space `device_edit` or wide `rename_devices`; the hub and the device online, the space disarmed unless the device does not report to the monitoring station |
| `update_device_settings` | space `device_edit`; the hub online, the space disarmed. The room needs `has_system_settings_permissions` or wide `manage_rooms`, the firmware hub `fw_updates_commands` |
| `update_hub_settings` | per setting, with the space disarmed and the hub online and not busy: `has_system_settings_permissions` for most, hub `en54_access_level_2` for EN54 ones, hub `hub_adv_params` and role `:admin` (or a Pro or an employee) for the server connection loss, `settings_edit` and role `:admin` (or a Pro or an employee) for the geofence |
| `scenarios` | space `scenario_edit` or wide `manage_automation_scenarios`; the hub online and not busy, the space disarmed unless the wide feature is on |
| `enable_scenario`, `disable_scenario` | nothing on the member: the scenario's `view_state`, which any inactive state disables (`insufficient_permissions` is one) |
| `devices`, `rooms` | space `structure_visibility` |
| `groups` | it lists only the groups whose entry is `:enabled` |
| `notifications` | `notification_info.are_notifications_accessible`, never `event_visibility` |
| `take_photo` | the device's entry in the hub's `photo_on_demand_device_permissions`: always, while armed, or after an alarm until `capture_photo_available_until`; the device not bypassed, and not offline, updating, in a walk test, saving its battery, waiting for migration, or failed to be added or transferred |
| `notification_media` | the photos' `visibility`: everyone, or a whitelist holding the account's id; an employee also needs the hub's photo viewing action |

Wide permissions count only with the hub feature `wide_access_first_iteration`. A plain user or an admin has
the `wide_space_permissions` the gateway sends; the app gives a Pro or an employee all of them when it has
`has_system_settings_permissions`. The role grants no permission by itself: an admin passes these checks
through the permissions the gateway sends it, except that `:admin` alone may mute every fire detector, and
the two hub settings above need it on top of their permission.

## Live video

An Ajax camera or recorder plays over WebRTC: the browser receives the media itself, and the back-end only
relays the signaling between it and the cloud. `video_channels(space_id)` lists the channels of the space's
cameras, `Streams` builds the streams the app asks for, and `live_video` opens the session. This follows the app
3.59 and was never tested: the koti space has no camera.

```ruby
channel = cloud.video_channels(space.id).first
view = Ajax::Sdk::Cloud::Streams::View.new(channel:, number: 1, quality: :main)
streams = [Ajax::Sdk::Cloud::Streams.live(view, tag: 0), Ajax::Sdk::Cloud::Streams.audio(view, tag: 1)]
live = cloud.live_video(space.id, channel.video_edge_id, streams)

Thread.new { live.each { |signal| browser.send(signal.to_json) } } # { iceServers: }, the camera's offer, candidates
live.answer(sdp)                                                   # what the browser sends back
live.candidate(candidate, sdp_mid:, sdp_mline_index:)
live.close                                                         # when the browser leaves
```

`each` gives each signal as the browser takes it: `{ iceServers: }` for its `RTCPeerConnection`, `{ type:, sdp: }`
for `setRemoteDescription`, `{ candidate:, sdpMid:, sdpMLineIndex: }` for `addIceCandidate`. What the app does,
which the browser can repeat:

- It builds its peer connection from the ICE servers, with max-bundle, and adds no track or data channel of
  its own, so it cannot offer first (deduced from the code, not seen on the wire); it answers the far end's
  offer as it is. Should an offer arrive while one of its own is pending, it rolls its own back.
- Both sides trickle their candidates, with no end of candidates. Once connected, the app reports it once with
  `established(latency:, candidate_type:, network:)`, read from its stats: a browser's `srflx` is `:reflexive`,
  and a `prflx` candidate or an unknown network goes as `:unspecified`.
- `ask_streams` sends every stream the session carries now, each time the list changes. Once the cloud's init
  arrives, `each` sends the list once more, as the app does when its signaling is ready; a change made before
  waits for it. The app ignores the cloud's answer to it, and so does `each`.
- Talk-back: the audio stream asks for it with `talk_back: true`; the app then adds a send-only audio track in a
  stream whose id is `voice`, and offers again (`live.offer`). A browser cannot choose a stream id: it would
  have to rewrite the `a=msid:` line of its offer, which nothing here has tried.
- One session per camera serves all its channels; the app ends it with `close` after 5 s without a player, and
  never half-closes it. The far end also opens a data channel on it, for the archive, the timeline and PTZ
  (see [Camera data channel](#camera-data-channel)).
- When the session fails (`ReadError`: `:permission_denied`, `:video_edge_is_offline`, `:video_edge_not_found`,
  `:bad_request`) or the connection drops, the app starts over after a second, gives each try 30 s and waits up
  to a minute between tries. A back-end decides for itself. A session runs once: after `each` returns, its
  writes raise `IOError`, and a new session starts over with `live_video`.

Each channel's permissions sit in `current_member(space_id)`, under `devices_permissions`,
`video_edge_permissions`, `channel_permissions` and `active.permissions`: `:view_live_stream` for live video,
`:view_archive`, `:sound` for the sound and talk-back, and `:ptz`, which `ptz: true` takes on top of the
channel's `ptz` capability.

## Recordings

A camera or recorder keeps its recordings on its own storage, and a channel with the cloud archive also in the
Ajax cloud. The SDK gives the days that hold some, the cloud archive's fragments and their addresses, and
exports; it hands out addresses and never touches the media. This follows the app 3.59 and was never tested:
the koti space has no camera.

```ruby
channel = cloud.video_channels(space.id).first
cloud.archive_days(channel)                       # the days with recordings; source: :device for the camera's own
list = cloud.cloud_fragments(channel, during: (Time.now - 3600)..Time.now)
archive = cloud.cloud_archive(channel)            # quality: :sub for the sub stream
Thread.new { archive.each { |content| browser.send(content.raw.to_json) } }
archive.get(*list.fragments.map(&:id))            # the tag its answers carry back
archive.close
```

- `archive_days` reads `get_channel_calendar` as the app's `b151` does: a byte per day from `start_day`, each
  recorded day shifted, in days, by the offsets of the last `tz_map` entry not after it, then each date once,
  in that order, as UTC dates.
- `cloud_fragments` and `cloud_metadata_fragments` ask for whole seconds and give a `FragmentList`: its
  `fragments` (id, start, duration in seconds), and `utc_offsets`, the UTC offset in force from each time on,
  which the app's timeline shows local time with. There are no pages: the app asks again from the end of the
  last fragment it has, and keeps the main and the sub stream apart.
- `cloud_archive` and `cloud_metadata` open the content stream with its init. `each` gives the answers as they
  come: `FragmentContent` (`tag`, `fragment_id`, `status`, `content_url`, `content_url_expires_at`, which the app
  never reads), `FragmentPartContent` (with the `content_url_headers` to fetch it with) and the video stream's
  `Init`. Ask from one thread at a time, as the app does.
  - On video, every `get` and `get_part` (a fragment from an offset in seconds, sent in whole milliseconds, as
    the app seeks on the sub stream) carries the current tag, from `"-1"`; `seek` moves it on, as the app does
    when the user seeks, so the answers to earlier requests come back with an older tag and can be dropped.
    The app plays each video address, a fragmented MP4, as its own source.
  - On metadata, each `get` takes the next tag, from `"0"`. Each address serves the gzip of
    `StreamCloudArchiveMetadataFragmentsContentResponse.FragmentContent.Frames`: `entries`, each a `timestamp` in
    microseconds and the `data` of an `ajax.video.v1.metadata.A` (activity) or `Figures` (overlays).
    `Schemas.descriptor_set('v3/mobilegwsvc/service/stream_cloud_archive_metadata_fragments_content/response.proto',
    'ajax/video/v1/metadata/metadata.proto')` gives those schemas.
- The cloud refuses a stream with `ReadError` `:playback_limit_exceeded` or `:cloud_archive_not_found`.
- The camera's own archive plays over its WebRTC session: `Streams.archive` and `Streams.activity` ask for it,
  and the data channel seeks and plays it (see [Camera data channel](#camera-data-channel)).
- `export_archive(channel, ranges, quality:, audio:, source:)` asks for an export of the ranges, to the
  nanosecond, and returns its id; the file comes later as a notification whose `notification_media` holds its
  address, and the app saves it as MP4.

Each channel's `:view_archive` and `:export_archive` permissions sit with the others (see Live video).

## Camera data channel

A live or archive session with an Ajax camera (`stream_webrtc`) carries a WebRTC data channel, which the far
end opens: the app never creates it. The browser that plays the video talks to the camera over it, so the
back-end never sees it: playing, pausing and seeking the camera's archive, its timeline, PTZ, and metadata
frames such as overlays and thumbnails. Its messages are protobuf, `ajax.dcp.v1.ClientMsg` from the browser and `ajax.dcp.v1.ServerMsg`
from the camera, and the frames hold `ajax.video.v1.metadata` messages. `Schemas.descriptor_set` gives their
schemas to a front that encodes and decodes them:

```ruby
schemas = Ajax::Sdk::Cloud::Schemas.descriptor_set('ajax/dcp/v1/dcp.proto', 'ajax/video/v1/metadata/metadata.proto')
# a serialized FileDescriptorSet, each file after its imports: protobuf.js reads it with Root.fromDescriptor,
# from protobufjs/ext/descriptor, and keeps the proto field names (sync_marker)
```

What the app 3.59 does on the channel, never tested here (the koti space has no camera):

- **Framing.** Each message goes after its length, a little-endian 32-bit integer that counts these 4 bytes;
  a message can span several data channel messages. The app sets only the low byte of the length it sends,
  which is right under 256 bytes, as all its commands are.
- **Opening.** Once the channel is open, the app sends `hello` with
  `supported_compression_methods: [:CM_GZIP]`; the camera may then send `compressed`, the gzip of a
  `ServerMsg.Uncompressed` holding `frame_data` or `archive_timeline`.
- **Addressing.** Every command carries `tag`, the `dcp_tag` of the stream it is about, and `sync_marker`,
  which the app counts up from one command to the next; its `hello` carries neither. The app holds its
  commands while the channel buffers 1,024 bytes or more.
- **Commands.** `archive_play` (`speed`, 1.0), `archive_pause`, `archive_seek` (`ts`; when the previous seek
  was less than 200 ms before, `economy: true` at once and an exact seek of the same instant 200 ms later,
  otherwise one exact seek), `archive_play_range` (`ts_range` in whole seconds,
  `speed` 0, `loop` false), `archive_reopen` (points a stream at a new `tag`, type, filter and range);
  `ptz_move` (`speed_x`, `speed_y`), `ptz_zoom` and `ptz_focus` (`speed`, positive for zoom in and
  Focus+, negative for zoom out and Focus-; a tap sends 1, then 0 50 ms later, and a release sends 0). The app never sends `ptz_stop`,
  `archive_change_range` or `archive_multi_play_range`, and its PTZ home button does not use the channel.
- **Camera messages.** `archive_status` (playing or paused, and the position);
  `archive_timeline`, whose `seconds` holds a byte per second from `ts_range.min_value`, bit 0 set when that
  second is recorded, to merge or to replace as `update_type` says; `frame_data`, whose frames each hold
  the metadata message their `type` names (`Thumbnail`, a JPEG; `Figures`, overlays such as detection boxes, labels and lines; `A`, the
  activity; `PirMotion`; `RadarMotion`); `quality_report`; `hello`, which says whether `archive_reopen` works.

## Any method

Every gRPC method the app has is in the shipped schema table, and the client has a method for each of
the 609, named after its path: the service without `Service`, then the method unless it is `execute`,
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
a `Data` class per message (5,832) and a module per enum (908), each loaded on its first use, with YARD
and RBS signatures that Steep checks.

- A message is a value whose members are its fields, plus `raw`, the Hash google-protobuf decoded;
  `to_message` gives the Hash back. A field the cloud leaves out holds its protobuf default (`0`, `''`,
  `false`, `[]`, `{}`); a sub-message, a oneof member or an `optional` field is nil instead.
- An enum value is a short symbol without the prefix its values share (`:ok` for `BATTERY_STATE_OK`,
  `:unspecified` for 0), or the number of a value the app 3.59 does not know.
- A oneof gives the name of the member that is set through a reader named after it.
- A `Timestamp` becomes a `Time` in UTC, a `Duration` a Float of seconds, a wrapper (`StringValue`…)
  what it holds.

A response whose `success` shares a oneof with its `failure` (or `error`), as 585 of the 609 methods
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

`#bidi` sends its Array of requests and half-closes. A bidi call that must stay open while requests go
out as they come, as the app holds its WebRTC and cloud archive streams, is an `Exchange`:

```ruby
exchange = cloud.exchange(path).write(first_request)
Thread.new { exchange.each { |message| … } } # runs the call until it ends
exchange.write(next_request)                  # from any thread, sent in order
exchange.close                                # cancels the call, as the app ends it
```

The call ends when the gateway ends it, when a message is a failure (`each` raises it), or at `close`;
it never half-closes. `write` builds its message at once, so a request the path does not take raises
there; once `each` has returned, `write` raises `IOError`, and a request written between the gateway's end
and that return is dropped. An exchange runs once; without a block, `each` returns an Enumerator. Before
the first message, an expired session logs in again and the call starts over with every request written
so far.

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
