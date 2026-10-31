# Changelog

All notable changes to this gem are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Breaking:** `start`, `stop`, `pause`, `light_on` and `light_off` are gone from `Appliance`: the
  Miele app sends them differently in each family, and they come back that way, ovens first.
- **Breaking:** a hood's `fan_level=` refuses while its screen is pushed in, and `wake` writes back a
  Dop1 or Opcode hood's light instead of `DeviceAction` 2, as the app does.
- **Breaking:** `Miele::Sdk.appliance` and `Miele::Sdk.appliances` return the class of each
  appliance's family. The hood's `fan_level=`, `fan_run_on_time=`, `main_light=`, `setting` and
  `write_setting` moved to `Hood`, and `power_on` and `power_off` to `Oven`.
- **Breaking:** `remote_control?` follows the app for each family and answers nil where the app
  never reads `RemoteEnable`; `mobile_start?` and `local_control?` join it.
- **Breaking:** `dop2` reads without a query unless given an index, `write_dop2` leaves the
  indexes in the leaf unless given `with_index: true`, and `Dop1.setting_value` takes only the
  hood's answer.

### Fixed

- Requests to the account's cloud (`/V2`, MCS login and renewal) name a language (`Accept-Language`),
  without which it answers 500.
- Dop1 sections go out in lower-case hex, as the app writes them.
- `power_on` and `power_off` send what the app's oven module sends, without the 2/1583 opcode
  fallback taken from ha-miele-at-lan, and `power_off` takes a 500 as done, as the app does.
- Dop1 settings go out with structure version 1, and the README's filter example resets the
  operating hours (40012) instead of writing the filter limit (40010) to 0.
- DOP2 fields of every type the app knows decode and encode; strings lose their trailing NULs.

### Added

- Hoods as the app's hood module drives them, in Opcode, Dop1 and DOP2: typed reads of the fan,
  run-on, lights, filters, height, dehumidification and grease melting; fan, run-on, lights,
  filter resets, ambient colours, dehumidification, fragrance, grease melting and auto refresh,
  each by the protocol the app picks and after the checks it makes. These writes have not run
  against a real hood.
- Con@ctivity Plus and One, and ColorFlow.
- Hobs read as the app reads them: zones, minute minder, power doubling, Stop&Go, TempControl and
  the fan of a hob with vapour extraction.
- `LENGTH` on the generated Dop1 write sections the app builds from nothing.
- A class per appliance family, chosen by device type and protocol version as the Miele app's
  family modules claim them, and `Appliance#name=`.
- Ovens as the app's oven module drives them: typed reads of the device and program contexts,
  notifications, program groups, own programs and their steps, and the second cavity; program
  selection, parameters, start, stop, continue cooking, steam burst, the end of keeping warm and
  answers to notifications, each after the checks the app makes (`ActionUnavailableError`).
  These writes have not run against a real oven.
- `Appliance#modify`, which reads a typed object, changes it and writes it back.

- Typed values of the DOP2 and Dop1 objects the Miele app uses, generated from its classes under
  `Miele::Sdk::Objects::<Family>`: `Appliance#object` and `#write_object` at the addresses the app
  uses, and `State#extended_state` for hoods, hobs and Dop1 ovens.
- The Miele cloud next to the local channel, as the Miele app uses it: the cloud and login system of
  the account's country from the locales the app reads, MCS login or CIAM code exchange, a token
  renewed once across threads and kept in `token_file`, requests under `/V2`, local first and the
  cloud on a 404, `Miele::Sdk.appliances`, and the household key read from the account.

- `services`, the lower-case resource the Miele app reads, which EK057 and EK039W modules do not
  serve locally.

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
