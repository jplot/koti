# Changelog

All notable changes to this gem are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `PhotoOnDemandService/capturePhoto` is in the method table (`photo_on_demand_capture_photo`): the
  extractor now reads a request class whose name holds a `$`, and a response declared far from its method.

### Changed

- **Breaking:** ajax-sdk requires Ruby 4.0 or later, like the rest of koti. `grpc` and `google-protobuf` have
  shipped Ruby 4.0 binaries since 1.78.1 and 4.34.0 (February 2026); the cap at `< 4.0` was never needed.
- **Breaking:** a refused TOTP code is no longer followed by the next window's: the login sends the current
  code once, as the app sends the one typed, and raises `AuthenticationError` `:invalid_totp`. The next call
  answers the same two-factor request with the code of that time, as the app's next try does, and the calls
  that waited on a failed login raise its error instead of signing in again.
- **Breaking:** a login refusal without a reason has the reason `:unknown`, not `:bad_request`, as the app
  tells them apart; a two-factor request with no id raises `:two_fa_required` before anything is sent, as the
  app refuses it.
- **Breaking:** the shortcuts send what they are given, encoded as the app's request builders encode it, and
  leave the answer to the gateway, where they raised `ArgumentError` for what the app's screens would not
  offer:
  - `set_brightness` and `move_shutter` take any percentage and any device, the first named a dimmer, the
    second by its exact type;
  - `turn_on` and `turn_off` take any channel and any device, one of no family by its exact type, as the
    app's relay channel tile sends it;
  - `life_quality_history` and `take_photo` take any device, `take_photo` naming one the app does not list
    without a family;
  - `lock`, `unlock` and `unlatch` send a device of the hub `device_off` / `device_on` as a smart lock, a
    Yale lock too, and unlatch it with `device_off` as the app does; any other device gets
    `switch_smart_lock`;
  - `mute` sends no source for a mute button that names no command;
  - `Streams.live` adds metadata other than the app's four after them.

  They raise `ArgumentError` only where the app's builder has nothing to send (a device outside the hub, a
  mute without a mute button), and `TypeError` for a value its field cannot carry.
- **Breaking:** `events` no longer reopens its streams: the feed ends with the first stream that ends and
  raises what breaks one. It takes a `tracker:` to reopen with, which reports only the changes made meanwhile
  and reads back the notifications created since the last one yielded; `sleeper:` is gone.
- **Breaking:** the SIA receiver no longer rescues an exception of its block to print it with `warn` and
  go on: the exception ends that hub connection's thread, which Ruby reports, and the connection with it.
- **Breaking:** an `UNAUTHENTICATED` answer no longer logs in again and replays the call: the client drops
  the session, as the app does, and raises `GRPC::Unauthenticated`; the next call logs in again.
  `Session#login` is gone: `Session#ensure_login` signs in when no session is held and returns the call
  metadata, and `Session#forget` drops the refused token.
- `notifications` reads 20 by default (it read 50), the most the app asks for.
- **Breaking:** `Device.from` takes the typed `LightDeviceItem` and the `space_id:`.
- **Breaking:** `call`, `unary`, `server_stream`, `client_stream` and `bidi` return generated values
  instead of Hashes (`raw` keeps the Hash), and a response whose `success` shares a oneof with its
  `failure` gives its success or raises `ReadError` (a read) or `CommandError`, with `reason`, `failure`
  and `details`.

### Added

- `press_shutter(device)`: the shutter control request with no command, which the app's shutter tile button
  sends while the shutter's position is known; while it moves or its position is unknown, the button stops it.
- `Session#restart_login`: drops the two-factor request, as the app's back button on its code screen does,
  so the next call signs in from the password.
- `photo_on_demand?(device)`: whether the app shows a photo on demand button for the device, which the
  gateway sends a `photo_on_demand` property.
- `refused:` on `Ajax::Sdk.sia_events` and `Sia::Receiver.new`: a callable given each frame the receiver
  refuses, as a `Sia::Refusal` (the frame, the reply `:duh`, `:nak` or nil, and why), such as a frame
  another SIA key encrypted.
- `archive_days`, `cloud_fragments`, `cloud_metadata_fragments`, `cloud_archive`, `cloud_metadata` and
  `export_archive`: a channel's recorded days, the cloud archive's fragments and their addresses, and exports.
- `take_photo(device)`: a MotionCam's photo on demand, sent as the app names the camera's family;
  `Notification#image_resource` and `notification_media(space_id, notification_id)` give the photos of a
  notification and their pre-signed addresses.
- `video_channels(space_id)`, `Streams` and `live_video`: a live WebRTC session with an Ajax camera, whose
  signaling `LiveVideo` relays between the cloud and a browser in the shapes `RTCPeerConnection` takes.
- `Schemas.descriptor_set(*names)`: the schemas of the messages a camera's data channel carries
  (`ajax.dcp.v1`, `ajax.video.v1.metadata`), with what they import, for a front that encodes them.
- `exchange(path)`: a bidi call that stays open while requests are written from any thread, read with
  `each` and cancelled with `close`, as the app holds its WebRTC and cloud archive streams.
- `current_member(space_id)`: the signed-in account's role and permissions in a space, which the app reads to
  offer only what the account may do; the README lists what the app checks before each shortcut.
- `events(space_id)`: one feed of `Event`s (space, security, groups, rooms, devices, notifications) for a
  space, from four streams that reopen on their own and catch up on what they missed; `Cloud::Tracker`
  keeps the `SpaceState` behind it.
- Every page of a space's notifications: `notifications` takes `older_than:` or `newer_than:` (a
  notification's new `token`) and adds the notifications grouped under an offline one (`parent_id`);
  `notification_history` reads every page lazily, each most recent first.
- Shortcuts for everyday actions (`Cloud::Shortcuts`): switching, dimming, roller shutters, bypass, group
  arming, the security mode, the panic button, locks, muting, the EN54 fire reset, device and hub details
  and settings, scenarios, rooms, groups and LifeQuality history (`LifeQualityHistory`), built on the
  requests of the app 3.59.
- `Device` reads `space_id`, the `channels` of relays, light switches, sockets and valves (`Channel`, with a
  dimmer's brightness), a roller `shutter` (`Shutter`), a `lock` state, `life_quality` (`LifeQuality`) and a
  fire detector's `mute_command`.
- A client method for each of the app's 609 gRPC methods (`Cloud::Methods`), named after its path
  (`stream_light_devices`, `space_security_arm_group`), with YARD and RBS: it builds its typed request
  before sending, and Steep rejects a wrong keyword, type or enum symbol in calling code.
- Typed values for every cloud message the app's methods use, generated from the shipped schemas
  (`Cloud::Messages`, 5,832 `Data` classes and 908 enum modules, loaded on first use), with their RBS;
  `rake generate` rewrites them and `rake generate:check` fails when they drift.
- `Cloud::RefusedError`, the parent of `ReadError` and `CommandError`.
- Typed cloud values: `devices` returns `Device` values (type, room, states, malfunctions, `Battery`,
  signal level, temperature and the statuses that carry no value as `flags`) and `notifications` returns
  `Notification` values (time, event, transition, `Source`, folder, importance); both keep `raw`.
- Local SIA DC-09 receiver (`Ajax::Sdk.sia_events`, `Sia::Receiver`, CRC from `digest-crc`): accepts the hub's frames over
  TCP, checks their CRC and length, decrypts AES-CBC, checks the timestamp, answers ACK, NAK or DUH,
  and yields events with their SIA code, label, group and number (device or user). The SIA key is hidden from `inspect`.
- Cloud client over gRPC (`grpc`, `google-protobuf`, `rotp`): login with the password hash and
  two-factor authentication, reading spaces (every page), devices and notifications, and arming or
  disarming a space, plus a generic call by gRPC path whose streams yield to a block or return an
  Enumerator. A read-only mode blocks every command; a refused read raises `ReadError`.
- Cloud protobuf schemas and gRPC method table extracted from the official app, loaded at runtime.
- Configuration of the cloud account, the mobile gateway, the client identity and the SIA receiver
