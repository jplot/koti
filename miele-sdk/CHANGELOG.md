# Changelog

All notable changes to this gem are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Breaking:** `start`, `stop`, `pause`, `light_on` and `light_off` are gone from `Appliance`: the
  Miele app sends them differently in each family, and they will come back that way.
- **Breaking:** `service` is `services`, read at the lower-case path the app reads.
- **Breaking:** `remote_control?` follows the app for each family and answers nil where the app
  never reads `RemoteEnable`; `mobile_start?` and `local_control?` join it.
- **Breaking:** `dop2` reads without a query unless given an index, `write_dop2` writes without
  one, and `Dop1.setting_value` takes only the hood's answer.

### Fixed

- `power_on` and `power_off` send what the app sends, without the 2/1583 opcode fallback taken
  from ha-miele-at-lan.
- Dop1 settings go out with structure version 1, and the README's filter example resets the
  operating hours (40012) instead of writing the filter limit (40010) to 0.
- DOP2 fields of every type the app knows decode and encode; strings lose their trailing NULs.

### Added

- Configuration of the household GroupID and GroupKey, ports, timeouts and listener identity
  through `Miele::Sdk.configure`.
- MieleH256 exchanges: requests signed with HMAC-SHA256 and encrypted with AES-256-CBC, every
  answer checked against the household key, error statuses mapped to `Miele::Sdk::Error`
  subclasses.
- Appliance discovery over mDNS from the mDNS port, repeating the query so a lost packet does not
  hide an appliance.
- Reading the REST resources of an appliance and of its Wi-Fi module, with the 74 device types and
  the protocol versions of the Miele app.
- `State` with named statuses, program types and program phases, times in seconds, temperatures
  in °C, door, failure, remote control, light, hood fan level and hob plates, and the program
  names of ovens, dishwashers, dish warmers, coffee systems, washing machines and tumble dryers.
- State commands: wake, and power through DOP2 with the wake-and-retry sequence of sleeping
  appliances. Commands and writes have not run against a real appliance yet.
- DOP2 leaves: decoding and encoding of every field type, reading and writing.
- Hood commands over Dop1: fan level, fan run-on time, main light and settings.
- Pushed events through `Miele::Sdk.events`: mDNS announcement as a household peer, a signed
  HTTP endpoint, enrollment of each appliance and withdrawal when the block ends. Pushes from a
  real hood and hob have been received; a real oven accepted the subscriptions and never pushed.
- Typed values (`Miele::Sdk::Schema`) from the classes the Miele app 4.19.0 reads and writes the
  local JSON with: `ident`, `supervision` and `software_update` return them, `State#attributes`
  and `Events::Event#attributes` read a state or a pushed change as one, and commands and
  enrollment build their bodies from them.
- RBS signatures for the whole public API.
