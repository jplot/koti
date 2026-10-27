# ajax-sdk

Unofficial Ruby client for [Ajax Systems](https://ajax.systems) alarms. It receives the events your
hub sends over SIA DC-09 on the local network, and it logs in to the cloud the official mobile app
uses to read your spaces, devices and history, and to arm or disarm a space.

> **Unofficial.** Ajax Systems does not endorse or support this gem. "Ajax" and the Ajax logo are
> trademarks of Ajax Systems. Use it with an account you control, at your own risk.

## Requirements

ajax-sdk talks gRPC, so it depends on the `grpc` and `google-protobuf` gems, which ship precompiled
binaries up to **Ruby 3.4** — this gem targets Ruby 3.4 (the rest of koti stays on 4.0). TOTP codes
are computed with [`rotp`](https://github.com/mdp/rotp).

## Account

Use a **dedicated account** added to your space, not your personal one, with **two-factor
authentication** turned on. koti answers the 2FA challenge itself from the TOTP secret the app shows
when you enable it. The password is never stored: pass its lowercase SHA-256 hash, which is what the
app sends over the wire.

```ruby
require "ajax/sdk"

Ajax::Sdk.configure do |config|
  config.email          = ENV.fetch("AJAX_EMAIL")
  config.password_sha256 = ENV.fetch("AJAX_PASSWORD_SHA256") # or: config.password = ENV.fetch("AJAX_PASSWORD")
  config.totp_secret    = ENV.fetch("AJAX_TOTP_SECRET")
end
```

## Local events (SIA DC-09)

The hub can report its events straight to a monitoring station over SIA DC-09, without the cloud. In
the Ajax app, set the hub's monitoring station to SIA DC-09 with the address and port of the machine
running koti, an object number (the account) and an encryption key of 16 characters or 32 hexadecimal
digits (the hub encrypts with AES-128), then choose the SIA-DCS format:

```ruby
Ajax::Sdk.configure do |config|
  config.sia_account = ENV.fetch("AJAX_SIA_ACCOUNT")
  config.sia_key     = ENV.fetch("AJAX_SIA_KEY")
  config.sia_port    = 18_083 # the default; config.sia_host defaults to 0.0.0.0
end

Ajax::Sdk.sia_events do |event|
  event.code   # => "BA"
  event.label  # => "Burglary Alarm"
  event.group  # => "1"
  event.number # => "3", the device; for arming and disarming, the user
end

Ajax::Sdk.sia_events.first(3) # lazily, without a block; iterate it with each, first or take, not next
```

The receiver answers each frame the way DC-09 expects: an ACK (encrypted like the frame), a NAK when
the timestamp falls outside `config.sia_timeband` (40 s behind, 20 s ahead by default), a DUH for
another account or for a clear frame while a key is set, and nothing for a frame whose CRC or length
is wrong. SIA carries alarms, arming and disarming, and device troubles such as a low battery (`XT`)
or a lost connection (`XL`); it carries no battery percentage, no signal level and no commands. While
no receiver runs, the hub reports the monitoring station as lost. The ACK goes out as soon as an event
is queued, so events still queued when `sia_events` stops are lost to koti, though the hub counts them
as delivered.

Set a key. Without one, any device on the network can send events the receiver accepts. With one, a
device on the network cannot make up an event, but a device placed between the hub and koti can still
replay or alter frames: DC-09 encrypts without authenticating.

`Ajax::Sdk::Sia::Receiver` is the server itself, for running it under your own supervision; its block
may be called from several threads at once, one per hub connection, and an exception it raises is
reported with `warn` without closing the connection.

## Reading

```ruby
cloud = Ajax::Sdk.cloud

space = cloud.spaces.first
space.name           # => "Home"
space.security_state # => :disarmed
space.online         # => true

cloud.devices(space.id)                 # => [{ hub_device: { … } }, …] one snapshot
cloud.notifications(space.id, limit: 20) # => [{ … }, …] most recent first
```

Spaces come back as {Ajax::Sdk::Cloud::Space} values; devices and notifications come back as plain
Hashes decoded from the gateway, with the whole payload under each entry. `spaces` reads every page.
A read the gateway refuses raises `Ajax::Sdk::Cloud::ReadError`, whose `reason` names why (for example
`:bad_request`).

## Commanding

```ruby
cloud.arm(space.id)            # arm
cloud.arm(space.id, ignore_alarms: true)
cloud.disarm(space.id)         # disarm
cloud.arm_night(space.id)      # arm to night mode
cloud.disarm_night(space.id)   # disarm from night mode
```

A command the hub refuses raises `Ajax::Sdk::Cloud::CommandError`, whose `reason` names why
(for example `:hub_offline`). Set `config.read_only = true` to make every command raise
`Ajax::Sdk::Cloud::ReadOnlyError` before anything is sent — the live specs use it so they never change
a real alarm's state.

## Any method

Every gRPC method the app has is in the shipped schema table, reachable by its path:

```ruby
cloud.call("/systems.ajax.api.mobile.v2.space.SpaceService/findUserSpacesWithPagination")
```

`#call` picks the call kind (unary, server stream, …) from the table; `#unary`, `#server_stream`,
`#client_stream` and `#bidi` are the direct accessors. Responses are Hashes.

A stream yields each message to the block, or returns an Enumerator without one; leaving it early
(`break`, `first`) closes the call. Streams have no deadline, every other call waits at most
`config.read_timeout` seconds (30 by default).

```ruby
path = '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service.stream_light_devices.StreamLightDevicesService/execute'
cloud.server_stream(path, { space_id: space.id }) { |message| … }
cloud.server_stream(path, { space_id: space.id }).first
```

## Errors

- `Cloud::AuthenticationError(reason)` — the login was refused (`:invalid_credentials`,
  `:account_locked`, `:invalid_totp`, …).
- `Cloud::CommandError(reason)` — the hub refused a command.
- `Cloud::ReadError(reason)` — the gateway refused a read.
- `Cloud::ReadOnlyError` — a command was blocked because the client is read-only.
- `Cloud::UnknownMethodError` / `Cloud::UnknownMessageError` — an unknown path or message name.
- `Sia::FrameError` — a frame is not valid DC-09 (`Sia::Message.parse`); the receiver stays silent on it.
- `ConfigurationError` — a missing or malformed setting: no password, no `sia_account` for `sia_events`,
  a SIA key that is neither 16 characters nor 32 hexadecimal digits.

## Live specs

Read-only checks against the real cloud run with the account in the environment:

```sh
AJAX_LIVE=1 AJAX_EMAIL=… AJAX_PASSWORD_SHA256=… AJAX_TOTP_SECRET=… bundle exec rspec spec/live
```

They log in (with 2FA) and read spaces, devices and notifications; the client is read-only, so no
command reaches the hub.

## Sources

The protobuf schemas and the gRPC method table are extracted from the official Android app
(`com.ajaxsystems` 3.59) and shipped as `lib/ajax/sdk/cloud/schemas/`. Transport is the `grpc` gem,
messages are `google-protobuf`, TOTP is `rotp`. The SIA event labels in `lib/ajax/sdk/sia/codes.tsv`
come from [pysiaalarm](https://github.com/eavanvalkenburg/pysiaalarm) (MIT License, notice in
`LICENSE`).

## License

[Mozilla Public License 2.0](../LICENSE).
