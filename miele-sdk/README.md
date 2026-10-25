# miele-sdk

Unofficial Ruby SDK for Miele@home appliances. It talks to them on the local network with the
household key, without any cloud service.

> **Unofficial.** This gem is not affiliated with, endorsed by or sponsored by Miele.
> Miele and Miele@home are trademarks of Miele & Cie. KG.

## Requirements

- Ruby 4.0 or later; no runtime dependency outside the standard library.
- Appliances with a Miele@home Wi-Fi module, already added to a household with the Miele app, on
  the same network as the host running the SDK.

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
oven.ident         # => {"DeviceType" => 13, "ProtocolVersion" => 4, "DeviceIdentLabel" => {…}, …}
oven.protocol_version  # => 4: DOP2 (3 or 4), or Dop1 (2)
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
state.remote_control?      # => true
state.light                # => :on
```

Hoods add `state.ventilation_step` (0 to 4), hobs `state.plates`, one `Plate` per cooking zone
(`step`, `remaining_heat`, `remaining_minutes`, `elapsed_minutes`, `timer_seconds`). Unknown
values read `:unknown`, and `state.raw` keeps the resource as served.

The other resources come as served: `settings`, `service`, `update` and `supervision` of the
appliance, `info`, `host_info` and `software_update` of its Wi-Fi module, and `get(path)` for any
other one.

## Commands

The appliance must accept remote control: enable it in its settings menu (named *Mobile
controllable* or *Remote control* depending on the model). Otherwise it answers 403 and the SDK
raises `Miele::Sdk::RemoteControlDisabledError`.

```ruby
oven.light_on
oven.light_off
oven.wake         # out of standby
oven.start        # ProcessAction 1; stop and pause as well
oven.power_on     # and power_off
```

An appliance answers 400 to a write that changes nothing, such as switching on a light already
on: `light_on`, `light_off`, `wake` and the hood commands treat it as done. A refused `start`,
`stop` or `pause` raises `Miele::Sdk::ResponseError`.

`power_on` and `power_off` write DOP2 leaf 2/1586. An appliance asleep answers 500: the SDK wakes
it, waits 3 seconds and tries again, twice at most, then sends the switch opcode on leaf 2/1583.

## DOP2

DOP2 is the binary protocol behind many settings and commands.

```ruby
leaf = oven.dop2(2, 1586)          # Miele::Sdk::Dop2::Leaf: unit, attribute, idx1, idx2, fields
leaf.fields[1]                     # => #<data Miele::Sdk::Dop2::Field type=:e8, value=4>

oven.write_dop2(Miele::Sdk::Dop2::Leaf.new(unit: 2, attribute: 1586, idx1: 0, idx2: 0,
                                           fields: { 1 => Miele::Sdk::Dop2::Field.new(type: :e8, value: 4) }))
```

Fields decode to booleans, signed and unsigned integers of 8 to 64 bits, strings, arrays and
structs; only scalar fields can be written, and a value outside its field's range raises
`ArgumentError`. Not every Wi-Fi module serves DOP2: EK057 and EK039W modules answer 404 to every
leaf, so `power_on` raises `Miele::Sdk::NotFoundError` on them.

## Hoods (Dop1)

Hoods reporting `ProtocolVersion` 2 answer Dop1 requests instead of DOP2.

```ruby
hood = Miele::Sdk.appliance('192.0.2.21')
hood.fan_level = 2           # 0 (off) to 3, 4 for boost, 5 for interval
hood.fan_run_on_time = 15    # 0, 5 or 15 minutes
hood.main_light = true
hood.setting(40_010)         # grease filter saturation, nil when the hood does not expose it
hood.write_setting(40_010, 0)
```

A value out of range raises `ArgumentError` before anything is sent. `Miele::Sdk::Dop1` builds
the requests, and `hood.dop1(request)` sends any other one.

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
per change, on the calling thread. Without a block it returns a lazy enumerator: iterate it with
`each`, `first` or `take`, since an external `next` never reaches the end of the stream and leaves
the subscriptions in place.

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

- Device types, statuses and program types: the Miele 3rd Party API documentation
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
- Program phases, the professional appliances and the second steam oven generation:
  [Home Assistant](https://github.com/home-assistant/core/tree/dev/homeassistant/components/miele).

Reading was checked against appliances with EK057 and EK039W Wi-Fi modules. Commands, DOP2 and
Dop1 writes have not run against a real appliance yet: they follow ha-miele-at-lan, which tested
them on its own appliances.

## Development

```sh
bundle install
bundle exec rake   # RuboCop, RSpec, YARD coverage, RBS validation, Steep
```

Live specs run against real appliances and never write to them: any request other than `GET` is
refused.

```sh
MIELE_LIVE=1 MIELE_GROUP_ID=… MIELE_GROUP_KEY=… MIELE_HOSTS=192.0.2.20,192.0.2.21 \
  bundle exec rspec --tag live
```

## License

Mozilla Public License 2.0, see [LICENSE](LICENSE).
