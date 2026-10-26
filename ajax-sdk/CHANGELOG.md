# Changelog

All notable changes to this gem are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Cloud client over gRPC (`grpc`, `google-protobuf`, `rotp`): login with the password hash and
  two-factor authentication, reading spaces, devices and notifications, and arming or disarming a
  space, plus a generic call by gRPC path. A read-only mode blocks every command.
- Cloud protobuf schemas and gRPC method table extracted from the official app, loaded at runtime.
- Configuration of the cloud account, the mobile gateway, the client identity and the SIA receiver
