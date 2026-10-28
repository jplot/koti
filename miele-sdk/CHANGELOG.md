# Changelog

All notable changes to this gem are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Configuration of the household GroupID and GroupKey, ports, timeouts and listener identity
  through `Miele::Sdk.configure`.
- MieleH256 exchanges: requests signed with HMAC-SHA256 and encrypted with AES-256-CBC, every
  answer checked against the household key, error statuses mapped to `Miele::Sdk::Error`
  subclasses.
- Appliance discovery over mDNS from the mDNS port, repeating the query so a lost packet does not
  hide an appliance.
- Reading the REST resources of an appliance and of its Wi-Fi module, with device types named
  from Miele's documentation.
- `State` with named statuses, program types and program phases, times in seconds, temperatures
  in °C, door, failure, remote control, light, hood fan level and hob plates, and the program
  names of ovens, dishwashers, dish warmers, coffee systems, washing machines and tumble dryers.
- State commands: start, stop, pause, light, wake, and power through DOP2 with the wake-and-retry
  sequence of sleeping appliances. Commands and writes have not run against a real appliance yet.
- DOP2 leaves: decoding of every field type, encoding of scalar fields, reading and writing.
- Hood commands over Dop1: fan level, fan run-on time, main light and settings.
- Pushed events through `Miele::Sdk.events`: mDNS announcement as a household peer, a signed
  HTTP endpoint, enrollment of each appliance and withdrawal when the block ends. Pushes from a
  real hood and hob have been received; a real oven accepted the subscriptions and never pushed.
- Typed values (`Miele::Sdk::Schema`) from the classes the Miele app 4.19.0 reads and writes the
  local JSON with: `ident`, `supervision` and `software_update` return them, `State#attributes`
  reads the state as one, and commands and enrollment build their bodies from them.
- RBS signatures for the whole public API.
