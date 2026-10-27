# Changelog

All notable changes to this gem are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Local SIA DC-09 receiver (`Ajax::Sdk.sia_events`, `Sia::Receiver`): accepts the hub's frames over
  TCP, checks their CRC and length, decrypts AES-CBC, checks the timestamp, answers ACK, NAK or DUH,
  and yields events with their SIA code, label, group and number (device or user). The SIA key is hidden from `inspect`.
- Cloud client over gRPC (`grpc`, `google-protobuf`, `rotp`): login with the password hash and
  two-factor authentication, reading spaces (every page), devices and notifications, and arming or
  disarming a space, plus a generic call by gRPC path whose streams yield to a block or return an
  Enumerator. A read-only mode blocks every command; a refused read raises `ReadError`.
- Cloud protobuf schemas and gRPC method table extracted from the official app, loaded at runtime.
- Configuration of the cloud account, the mobile gateway, the client identity and the SIA receiver
