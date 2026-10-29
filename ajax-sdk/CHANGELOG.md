# Changelog

All notable changes to this gem are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Breaking:** `call`, `unary`, `server_stream`, `client_stream` and `bidi` return generated values
  instead of Hashes (`raw` keeps the Hash), and a response whose `success` shares a oneof with its
  `failure` gives its success or raises `ReadError` (a read) or `CommandError`, with `reason`, `failure`
  and `details`.

### Added

- Typed values for every cloud message the app's methods use, generated from the shipped schemas
  (`Cloud::Messages`, 5,828 `Data` classes and 907 enum modules, loaded on first use), with their RBS;
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
