# Changelog

All notable changes to this gem are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Breaking:** entertainment `stream` no longer reads the lights of the area before streaming nor puts them
  back after it: the bridge leaves them on the last frame.
- **Breaking:** `events` no longer reconnects, nor sends its request a second time as Net::HTTP would: it reads
  the stream once and raises `ConnectionError` when it breaks. `Events::Stream` takes the `last_event_id:` of
  an earlier stream to resume from; `sleeper:` is gone.
- When the stop fails, entertainment `stream` raises what ended the stream (the block's error, an interrupt or a
  timeout included, or a failed handshake) rather than the stop's error, which it raises only when nothing else
  did.

### Fixed

- The entertainment DTLS handshake sends a lost flight again after 1 s, then 2 s, and gives up after 5 s,
  as documented, instead of resending every 5 s and giving up after 20 s. A handshake losing three flights
  now fails at 5 s, where it succeeded at 15 s.
- An error reported in the event stream reaches the block as an event of kind `:error`, instead of ending the stream
  with `NoMethodError`. Its `resource_type` and `resource_id` are nil, and so is `Event#resource`.

### Added

- Configuration of the bridge address, identity, keys and timeouts through `Hue::Sdk.configure`.
- HTTPS connections pinned to the Signify root CA and to the configured bridge id, one
  keep-alive connection per thread and per fiber.
- CLIP v2 client mapping error statuses to `Hue::Sdk::Error` subclasses, partial success
  (207) included.
- Bridge discovery over mDNS, repeating the query so a lost packet does not hide the bridge.
- Pairing with the link button, returning the application key and the client key.
- A model and an entry point for each of the 47 resource types of the Bridge Pro firmware,
  offering only the operations the bridge accepts, with `owner`, `children` and `services`
  associations; deprecated fields are left out.
- Real-time events through `Hue::Sdk.events` and `Events::Stream`, which resumes from the id of the last
  message read (`Last-Event-ID`).
- Entertainment streaming over DTLS 1.2 with a pre-shared key (`require 'hue/sdk/entertainment'`,
  with the `ffi` gem), through the libssl Ruby's OpenSSL extension is linked with.
- RBS signatures for the whole public API.
- Typed values generated from the Hue app's own classes: `attributes` reads a resource as a
  `Hue::Sdk::Schema` value whose signature tells which fields the bridge always sends, and
  `update` and `create` accept the request classes the app sends (`Schema::LightUpdate`,
  `Schema::RoomAdd`…).
- Automations as typed values: `behavior_instance` reads its configuration with a class per script and its
  state with `BehaviorState`, and takes `BehaviorInstanceAdd` and `BehaviorInstanceUpdate`, triggers included.
  `Schema::BEHAVIOR_SCRIPTS` names the scripts.
- The configurations of accessories and MotionAware areas as typed values, under the scripts `hue_accessories`,
  `tap_switch`, `motion_sensor` (cameras) and `contact_sensor`. A configuration that would not go back whole stays a hash.
- `Event#attributes` gives the changes of an event as a typed value, without a request.
- `Hue::Sdk.settings` reads the time zone of the bridge over CLIP v2 and its other settings over CLIP v1. `update` writes
  its time zone, its clock, the blocking of plain HTTP and the consent to share statistics over CLIP v1, and keeps the
  values written, reading only the blocking of plain HTTP back, as the app does.
- Hue Secure through the Hue account's cloud, loaded apart by `require 'hue/sdk/secure'` and never tested with a
  Hue Secure device: login through Auth0 with PKCE and the Hue app's client id, given by the caller; a token saved
  in mode 0600, kept current in the `token` setting, and renewed 30 s before it expires, once across threads; a
  client sending any request to the cloud with the token; the homes of the account over gRPC, with the `grpc` gem.
  `ResponseError` takes `source:`, so an error of the cloud reads `Hue cloud answered …`.
