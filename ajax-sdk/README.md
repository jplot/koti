# ajax-sdk

Unofficial Ruby client for [Ajax Systems](https://ajax.systems) alarms. It logs in to the cloud the
official mobile app uses and reads your spaces, devices and history, and arms or disarms a space.

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
Hashes decoded from the gateway, with the whole payload under each entry.

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

## Errors

- `Cloud::AuthenticationError(reason)` — the login was refused (`:invalid_credentials`,
  `:account_locked`, `:invalid_totp`, …).
- `Cloud::CommandError(reason)` — the hub refused a command.
- `Cloud::ReadOnlyError` — a command was blocked because the client is read-only.
- `Cloud::UnknownMethodError` / `Cloud::UnknownMessageError` — an unknown path or message name.

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
messages are `google-protobuf`, TOTP is `rotp`.

## License

[Mozilla Public License 2.0](../LICENSE).
