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
