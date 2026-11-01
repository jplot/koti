# Changelog

All notable changes to this gem are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `PhotoOnDemandService/capturePhoto` is in the method table (`photo_on_demand_capture_photo`): the
  extractor now reads a request class whose name holds a `$`, and a response declared far from its method.

### Changed

- `notifications` reads 20 by default (it read 50), the most the app asks for.
- **Breaking:** `Device.from` takes the typed `LightDeviceItem` and the `space_id:`.
- **Breaking:** `call`, `unary`, `server_stream`, `client_stream` and `bidi` return generated values
  instead of Hashes (`raw` keeps the Hash), and a response whose `success` shares a oneof with its
  `failure` gives its success or raises `ReadError` (a read) or `CommandError`, with `reason`, `failure`
  and `details`.

### Added

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
