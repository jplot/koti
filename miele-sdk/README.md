# miele-sdk

Unofficial Ruby SDK for Miele@home appliances. It talks to them on the local network with the
household key and, where an appliance does not answer there, through the Miele cloud, as the Miele
app does.

> **Unofficial.** This gem is not affiliated with, endorsed by or sponsored by Miele.
> Miele and Miele@home are trademarks of Miele & Cie. KG.

## Requirements

- Ruby 4.0 or later; no runtime dependency outside the standard library.
- Appliances with a Miele@home Wi-Fi module, already added to a household with the Miele app, on
  the same network as the host running the SDK.
- For the cloud, which is optional: the Miele account the appliances were added with.

The SDK does not add appliances to a household, update their firmware, or touch their Wi-Fi
settings.

## Installation

```ruby
# Gemfile
gem 'miele-sdk'
```

RBS signatures ship in `sig/`, so Steep checks code calling the SDK.

## Configuration

```ruby
require 'miele-sdk'

Miele::Sdk.configure do |config|
  config.group_id = ENV.fetch('MIELE_GROUP_ID')     # 16 hexadecimal digits
  config.group_key = ENV.fetch('MIELE_GROUP_KEY')   # 128 hexadecimal digits
end
```

| Setting | Default | Purpose |
|---|---|---|
| `group_id` | — | household GroupID |
| `group_key` | — | household GroupKey, which signs and encrypts every exchange |
| `port` | `80` | HTTP port of the appliances |
| `open_timeout` / `read_timeout` | `5` / `10` s | requests to the appliances |
| `listener_port` | `18082` | port the event listener binds |
| `listener_fab` | `000999` and six digits from the host name | identity of this host as a household peer |
| `advertise_address` | the local address that routes to the appliances | address announced for pushed events |
| `country` | — | ISO code of the Miele account's country, which picks its cloud |
| `email` / `password` | — | the account, in countries that log in by e-mail and password |
| `ciam_client_id` | — | OAuth client id of the Miele app, in countries that log in through CIAM |
| `token_file` | — | where the account's token is kept between runs (mode 0600) |
| `cloud_token` | — | a token saved from `token.to_json`, to start without logging in |
| `locales_host` | `https://rest-eu.domestic.miele-iot.com` | where the app reads each country's cloud |

### The household key

Every request is signed with HMAC-SHA256 and its body encrypted with AES-256, both with the
household GroupKey; every answer must carry a valid signature too. The GroupID is public: each
appliance announces it (`Miele::Sdk.discover.first.group_id`). The GroupKey is held by the Miele
app and by the appliances; this SDK never fetches it.
[ha-miele-at-lan](https://github.com/tiehfood/ha-miele-at-lan) can retrieve it once from the
Miele cloud. Keep it secret: it controls every appliance of the household.

## Discovery

Appliances announce themselves over mDNS (`_mieleathome._tcp`).

```ruby
appliance = Miele::Sdk.discover.first
appliance.name         # => "Miele H7164BP"
appliance.host         # => "192.0.2.20"
appliance.device_type  # => 13
appliance.group_id     # => "0123456789ABCDEF"
```

Miele appliances only answer queries sent from the mDNS port, so the query leaves from port
5353, shared with the system's own responder. It is sent again after 1 and 3 seconds, since
Wi-Fi drops multicast packets; the default 4-second window fits three queries.

## Reading

```ruby
oven = Miele::Sdk.appliance('192.0.2.20')
oven.fab           # => "000123456789", the fabrication number
oven.device_type   # => :oven_microwave
oven.ident         # => #<data Miele::Sdk::Schema::DeviceIdentification device_type=13, …>
oven.protocol_version  # => 4: DOP2 (3 or 4), or Dop1 (2)
oven.protocol     # => :dop2_hdr
oven.tech_type     # => "H7164BP", the model

state = oven.state
state.status               # => :running
state.program_type         # => :normal_operation, numbered by the protocol version
state.program_id           # => 13
state.program              # => :fan_plus, where the Miele app names programs
state.program_phase        # => :heating_up_phase
state.remaining_time       # => 5400, in seconds
state.temperatures         # => [180.5, nil, nil], in °C, nil where nothing is measured
state.target_temperatures  # => [180.0, nil, nil]
state.door_open?           # => false
state.remote_control?      # => true; mobile_start? and local_control? as well
state.light                # => :on
```

Hoods add `state.ventilation_step` (0 to 4), hobs `state.plates`, one `Plate` per cooking zone
(`step`, `remaining_heat`, `remaining_minutes`, `elapsed_minutes`, `timer_seconds`). Unknown
values read `:unknown`, `state.raw` keeps the resource as served, and `state.attributes` gives it
as a typed value.

`remote_control?`, `mobile_start?` and `local_control?` read `RemoteEnable` the way the Miele app
does for the appliance's family: ovens, warming drawers and coffee machines compare its first
value to 15 or 7, dishwashers and laundry appliances test its bits. They answer nil for the other
families, such as hoods and hobs, for which the app never reads it.

`supervision` and `software_update` come as typed values too, and `services` as served: the
services the Miele app reads (camera, remote update, Con@ctivity), which EK057 and EK039W modules
do not serve locally (404). The other resources come as served, the app reading none of them:
`settings`, `service` and `update` of the appliance, `info` and `host_info` of its Wi-Fi module,
and `get(path)` for any other one.

### Typed values

`Miele::Sdk::Schema` holds the classes the Miele app 4.19.0 reads and writes the local JSON with,
as `Data` values. A member is its JSON key in snake case (`ProgramID` is `program_id`, `SWIDs` is
`sw_ids`), and it may be nil wherever the app's class lets it be null, as every member of the
ident and of the state.

| Value | Read from, or sent to | Miele app class |
|---|---|---|
| `DeviceIdentification`, with `DeviceIdentificationLabel` and `XkmIdentificationLabel` | `ident`, and `event.attributes` for `/Ident/` | `DeviceIdentificationDto` and its two labels |
| `DeviceState` | `state.attributes`, `event.attributes` for `/State/`, and the body of each state command | `DeviceStateDto` |
| `SuperVision` | `supervision`, the peers in `entries` | `SuperVisionDto` |
| `ModuleUpdateInfo` | `software_update` | `ModuleUpdateInfoDto`, and `CheckUpdateResponseBodyDto` for `ReleaseNotes` |
| `SuperVisionDevice` and `Subscription` | the bodies `events` puts and posts to enroll an appliance | `SuperVisionDeviceDto` and `SubscriptionDto` |

```ruby
Miele::Sdk::Schema::DeviceState.from(json)               # a parsed resource; unknown keys are ignored
Miele::Sdk::Schema::DeviceState.new(light: 1).to_body    # => {"Light" => 1}
Miele::Sdk::Schema::SuperVisionDevice.new(signal: true)  # ArgumentError: missing keyword: :show
```

A value refuses a member its class lacks, and `to_body` refuses a required member left nil.

## Commands

The appliance must accept remote control: enable it in its settings menu (named *Mobile
controllable* or *Remote control* depending on the model). Otherwise it answers 403 and the SDK
raises `Miele::Sdk::RemoteControlDisabledError`.

```ruby
oven.wake         # out of standby
oven.power_on     # and power_off
```

An appliance answers 400 to a write that changes nothing: `wake` and the hood commands treat it as
done.

`power_on` writes 4 to DOP2 leaf 2/1586, as the Miele app's oven module does; its other families
switch on in their own way, which will come with them. An appliance asleep answers 500:
like the app, the SDK then sends `DeviceAction` 2, waits 3 seconds and writes again, giving up
after three attempts where the app sets no limit. `power_off` writes 1 to the same leaf.

Starting, stopping or pausing a program, and the light, take a different request in each family
of the app: a user request on DOP2 leaf 2/1583 for DOP2 appliances, `ProcessAction` for Dop1
dishwashers and laundry appliances, and no light at all for ovens. They will come back per family.

## DOP2

DOP2 is the binary protocol behind many settings and commands.

```ruby
leaf = oven.dop2(2, 1586)          # Miele::Sdk::Dop2::Leaf: unit, attribute, idx1, idx2, fields
leaf.fields[1]                     # => #<data Miele::Sdk::Dop2::Field type=:e8, value=4>
oven.dop2(1, 131, idx1: 0, idx2: 1)  # an index, as the app polls its leaves

oven.write_dop2(Miele::Sdk::Dop2::Leaf.new(unit: 2, attribute: 1586, idx1: 0, idx2: 0,
                                           fields: { 1 => Miele::Sdk::Dop2::Field.new(type: :e8, value: 4) }))
```

Fields decode and encode every type the Miele app knows: booleans, signed and unsigned integers of
8 to 64 bits, floats, enums, strings, structs, arrays of each scalar and arrays of structs. A value
outside its field's range raises `ArgumentError`, and a string is read without its trailing NULs
and written with one, as the app writes it. `dop2` reads `/DOP2/{unit}/{attribute}` without a
query unless given an index: the app's live observation reads the first way, its one-shot reads
with `idx1: 0, idx2: 0` and its polls with `idx1: 0, idx2: 1`. `write_dop2` leaves the indexes in
the leaf, as the app's oven, dishwasher and laundry modules do; `with_index: true` also puts them
in the path, as its hood and coffee modules do. Not every Wi-Fi module serves DOP2: EK057 and
EK039W modules answer 404 to every leaf, so `power_on` raises `Miele::Sdk::NotFoundError` on them.

## Hoods (Dop1)

Hoods reporting `ProtocolVersion` 2 answer Dop1 requests instead of DOP2.

```ruby
hood = Miele::Sdk.appliance('192.0.2.21')
hood.fan_level = 2           # 0 (off) to 3, 4 for boost, 5 for interval
hood.fan_run_on_time = 15    # 0, 5 or 15 minutes
hood.main_light = true
hood.setting(40_010)         # the current grease filter limit, nil when the hood does not expose it
hood.write_setting(40_012, 1)  # resets the grease filter's operating hours (40_013: charcoal)
```

Settings (programming functions, Dop1 object 1201) go out with structure version 1, as the app
sends them.

A value out of range raises `ArgumentError` before anything is sent. `Miele::Sdk::Dop1` builds
the requests, and `hood.dop1(request)` sends any other one.

## Typed objects

The objects behind DOP2 leaves and Dop1 requests come typed, generated from the Miele app's own
classes: `Miele::Sdk::Objects::<Family>` (`Oven`, `Hood`, `Hob`, `Dishwasher`, `Laundry`,
`CoffeeGen7`, `CoffeeCm7`, `Drawer`) holds a `Data` class per object and a module per enum, each
loaded on its first use. Names follow the app's: `GLOBAL_PS_Select` is `GlobalPsSelect`, its getter
`ProgId` the member `prog_id`, and the value `GLOBAL_DS_MAINSTATEEXTERN_RUNNING` the symbol `:running`.

```ruby
steps = oven.object(Miele::Sdk::Objects::Oven::GlobalOpProgramInfoCA)  # 2/213, idx 0/1, as the app polls it
steps.amount_of_steps  # => 3
steps.infos1           # => [:beliebige_ebene, 65000]: a value the app does not know stays a number

select = dishwasher.object(Miele::Sdk::Objects::Dishwasher::GlobalPsSelect)       # 2/1577, idx 0/0
dishwasher.write_object(select.with(prog_id: :dw_prg_intensiv), [2, 1577, 0, 0])  # where the app writes it back

hood.object(Miele::Sdk::Objects::Hood::GlobalSfValue, [2, 105, 9001, 1])  # an index the app computes
hood.state.extended_state.luefter_1.luefterstufe_luefter_1               # the fan level, as the app reads it
```

- `ADDRESSES` lists where the app reads or writes a DOP2 object: `[unit, attribute]` when it sends
  no index, else `[unit, attribute, idx1, idx2]`, nil for an index it computes. `object` reads at
  the first unless given another; `write_object` writes only where it is told, the app writing some
  objects elsewhere than it reads them. Both raise `ArgumentError` while an index is left to compute.
- An attribute the leaf lacks reads nil. `write_object` writes back the attributes as read, each
  changed member in the wire type it was read in, and raises `ArgumentError` for a member it did not
  read, as the app's setters do.
- A Dop1 object decodes its sections, bit fields and byte order (`from(bytes)`), and `to_bytes`
  gives what a write section sends.
- `state.extended_state` decodes `ExtendedState` into the object the app builds from it: the hood's
  by `ProtocolVersion` (1 to 4), and the Dop1 and Opcode hob's. It is nil for the other
  families, which read it otherwise, and when the appliance serves none, as they do switched off.

Only the objects the app's family modules use are generated: 402 DOP2 classes, 468 Dop1 classes and
336 enums from the app 4.19.0. None has been read from an appliance yet: the hood and hob tried
served an empty `ExtendedState`, being off, and the oven serves DOP2 only through the cloud.

## Cloud

After pairing, the Miele app reaches the appliances only through the Miele cloud, and some Wi-Fi
modules serve no DOP2 locally (EK057 and EK039W answer 404). Given the account (an e-mail, a saved
`cloud_token` or an existing `token_file`), the SDK uses the cloud where an appliance does not answer
locally. A cloud built from the copy the app bundles, when the locales did not answer, is not kept: the
next call asks them again.

```ruby
Miele::Sdk.configure do |config|
  config.country = 'FR'
  config.token_file = File.expand_path('~/.config/koti/miele-token.json')
  config.ciam_client_id = ENV.fetch('MIELE_CIAM_CLIENT_ID')  # CIAM countries
  config.email = ENV.fetch('MIELE_EMAIL')                     # MCS countries
  config.password = ENV.fetch('MIELE_PASSWORD')
end

Miele::Sdk.appliances      # the account's appliances, reached by the name of their module
oven.dop2(1, 1585)         # 404 locally, so through the cloud, and so is every later DOP2 request
```

**Local first.** An appliance sends every request locally. When it answers 404 and an account is
set, the request goes to the cloud under `/V2`, and every later one for the same resource of that
appliance (DOP2, Dop1, `State`…) goes there directly; a Dop1 request names the module in `Host`, as
the app does. Without an account nothing changes. With an account and neither `group_id` nor
`group_key`, the local channel signs with the household key the account holds (`/V2/GroupKeyId/`).

**Logging in.** The SDK reads the cloud of the account's country and how its accounts log in where
the app reads them (`/V3/Locales` on `locales_host`), or from the copy the app bundles when they do
not answer. Then:

- **MCS** (e-mail and password): it logs in and renews the token past half its life.
- **CIAM** (a web page; France since October 2026): log in once in a browser.

  ```ruby
  session = Miele::Sdk.cloud.session
  puts session.authorize_url  # open it and log in
  session.exchange(code)      # the code of the miele://oauth2-code/?code=… address the page then opens
  ```

  The browser cannot open that `miele://` address: take the code from the address it shows, or from
  the network tab of its developer tools. The token is renewed past 90 % of its life. Keep it in
  `token_file` so that the next run starts from it.

`ciam_client_id` is the Miele app's OAuth client id (`MA.Constants.CdcKeys.ClientId` in
`Miele.Modules.Authentication`); the gem does not ship it. The cloud client follows the
environment's proxy settings; the local one never does.

The cloud channel has not run against the live cloud yet: France switched to CIAM before the first
login.

## Events

```ruby
hosts = Miele::Sdk.discover.map(&:host)

Miele::Sdk.events(hosts:) do |event|
  puts "#{event.fab} #{event.resource}: #{event.content}"
end
```

`Miele::Sdk.events` announces this host over mDNS as a peer of the household, listens on
`listener_port`, and asks each appliance to push its changes to it: it declares this host in the
appliance's `SuperVision` and subscribes to `/State/`, `/State/Light/`, `/State/Status/` and
`/Ident/`. It then blocks and yields a `Miele::Sdk::Events::Event` (`fab`, `resource`, `content`)
per change, on the calling thread. `event.attributes` reads `content` as a typed value: a
`DeviceIdentification` for `/Ident/`, else a `DeviceState`, of which `/State/Light/` and
`/State/Status/` fill only `light` or `status`. Without a block it returns a lazy enumerator:
iterate it with `each`, `first` or `take`, since an external `next` never reaches the end of the
stream and leaves the subscriptions in place.

When the block breaks or raises, the subscriptions are deleted and `SuperVision` stops showing
this host; the peer entry itself stays listed. An appliance that cannot be reached at that point
keeps its subscriptions, with a warning on stderr; the next run deletes them, since
`listener_fab` does not change. An appliance that cannot be enrolled is skipped, with a warning.

Every push must be signed with the household key, or it is refused; a refused request that claims
the household's GroupID is reported on stderr. The date a push carries is not checked: a push
captured on the network can be sent again.

The appliances must reach `listener_port` on this host and resolve its name over mDNS. When they
sit on a network of their own (an IoT VLAN), allow TCP from that network to this host's
`listener_port` and relay mDNS between the two networks. Set `advertise_address` when the host has
several network interfaces.

Enrollment and withdrawal have run against real appliances, leaving their subscriptions as they
were. Pushes from a real hood and a real hob, which has no `SuperVision`, have been received,
verified and decoded. A real oven accepted the same subscriptions and never pushed, not even while
heating; follow such an appliance by reading its `state` at intervals.

## Errors

| Error | Raised when |
|---|---|
| `Miele::Sdk::ConfigurationError` | the GroupID or GroupKey is missing or malformed |
| `Miele::Sdk::ConnectionError` | the appliance cannot be reached, or drops the connection |
| `Miele::Sdk::SignatureError` | an answer is not signed or encrypted with the household key |
| `Miele::Sdk::AuthenticationError` | the appliance refuses a read: the key does not match its own |
| `Miele::Sdk::ResponseError` | the appliance answers with an error status; carries `status` |
| `Miele::Sdk::NotFoundError` | the appliance does not serve that resource, or the GroupID is not its own (a `ResponseError`) |
| `Miele::Sdk::RemoteControlDisabledError` | the appliance refuses a command (a `ResponseError`) |
| `Miele::Sdk::Dop2::DecodeError` | a DOP2 leaf has an unknown type or ends too early |

All of them inherit from `Miele::Sdk::Error`. A value out of range raises `ArgumentError` before
anything is sent.

## Sources

- Device types: the 74 values of the Miele app 4.19.0's `DeviceType` enum, under the names given
  below where those sources name them.
- Statuses and program types: the Miele 3rd Party API documentation
  ([capabilities by device](https://developer.miele.com/docs/third-party-api/API_V1.1.x_capabilities_by_device.pdf)
  and its 2022 OpenAPI description). Statuses 144, 145 and 147, and 148 on hoods, take the names
  the Miele app 4.19.0 gives them; the app also gives the program types of DOP2 appliances, the
  last two of Dop1 ones, and the phases of hoods. The other phases come from Home Assistant core.
- Program names, in the default English of the Miele app 4.19.0, kept in
  `lib/miele/sdk/catalog/programs.tsv`: its DOP2 oven menus, its seven Dop1 oven tables, its
  dishwasher tables (DOP2 and Dop1), dish warmer labels, the drinks of a coffee system's standard
  profile and its nine washing machine and tumble dryer tables, each with the rule picking it. Its
  "Poit of herbal tea" reads `:pot_of_herbal_tea`.
- The local protocol (signing, DOP2 layout, Dop1 objects, power sequence, SuperVision):
  [ha-miele-at-lan](https://github.com/tiehfood/ha-miele-at-lan), building on the work of
  [MieleRESTServer](https://github.com/akappner/MieleRESTServer).
- Typed values: the JSON classes of the Miele app 4.19.0, read from its assemblies. A hood and a
  hob with EK039W modules serve no key these classes lack. `schema/README.md` tells how to check
  them against a newer version of the app.
- Program phases, the professional appliances and the second steam oven generation:
  [Home Assistant](https://github.com/home-assistant/core/tree/dev/homeassistant/components/miele).

Reading was checked against appliances with EK057 and EK039W Wi-Fi modules. Commands, DOP2 and
Dop1 writes have not run against a real appliance: they send what the Miele app 4.19.0 sends,
read from its code.

## Development

```sh
bundle install
bundle exec rake            # generated files, RuboCop, RSpec, YARD coverage, RBS validation, Steep
bundle exec rake generate   # rewrites lib/miele/sdk/objects/ from objects.json.gz
```

Live specs run against real appliances and never write to them: any request other than `GET` is
refused.

```sh
MIELE_LIVE=1 MIELE_GROUP_ID=… MIELE_GROUP_KEY=… MIELE_HOSTS=192.0.2.20,192.0.2.21 \
  bundle exec rspec --tag live
```

## License

Mozilla Public License 2.0, see [LICENSE](LICENSE).
