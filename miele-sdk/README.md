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

## Families

`Miele::Sdk.appliance(host)` reads `Ident` once and returns the class of the appliance's family,
by device type and protocol version as the Miele app's family modules claim them.
`Miele::Sdk.appliances` does the same from the ident the account lists, without reading it.

| Class | Device types | Protocol versions |
|---|---|---|
| `Miele::Sdk::Oven` | 12, 13, 15, 31, 39, 45 | 2, 3, 4 |
| `Miele::Sdk::Hood` | 18 | 1 to 4 |
| `Miele::Sdk::Hob` | 14, 27, 28 | 1, 2, 4 |
| `Miele::Sdk::Dishwasher` | 7, and 8 for a model starting with PG81 | 2 to 4 (8: 2) |
| `Miele::Sdk::WashingMachine` | 1, 3, 24 | 1 to 4 |
| `Miele::Sdk::TumbleDryer` | 2, 4 | 1 to 4 |
| `Miele::Sdk::CoffeeMaker` | 17 | 2 to 4 |
| `Miele::Sdk::CoolingAppliance` | 19, 20, 21, 32, 33, 34, 68 | 0, 1, 200, 201, 203 |
| `Miele::Sdk::WarmingDrawer` | 25 | 2 |

Any other appliance is a plain `Miele::Sdk::Appliance`. Each class reads and writes what
`Appliance` does; ovens and hoods add what their app modules send, and the other families will get
theirs. Every appliance takes a new name, written to `Ident` as the app writes it:

```ruby
oven.name = 'Cuisine'
```

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
(`step`, `remaining_heat`, `remaining_minutes`, `elapsed_minutes`, `timer_seconds`), from keys of
`State` the app does not read for hobs: `hob.zones` reads what it reads (see [Hobs](#hobs)). Unknown
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
after three attempts where the app sets no limit. `power_off` writes 1 to the same leaf and takes a
500 as done, as the app does. Both belong to `Miele::Sdk::Oven`.

Starting, stopping or pausing a program, and the light, take a different request in each family
of the app: a user request on DOP2 leaf 2/1583 for DOP2 appliances, `ProcessAction` for Dop1
dishwashers and laundry appliances, and no light at all for ovens. Ovens have theirs (see
[Ovens](#ovens)); the other families will get theirs.

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

## Hoods

`Miele::Sdk::Hood` reads and acts as the app's hood module does, in each protocol the app knows:
Opcode (1), Dop1 (2) and DOP2 (3 and 4).

```ruby
hood = Miele::Sdk.appliance('192.0.2.21')
hood.fan_level          # => 2: 0 to 3, 4 for boost, 5 for interval, 8 while it adjusts its pressure
hood.run_on             # => #<data RunOn setting=5, minutes_left=3>
hood.lights.main        # => #<data Light exists=true, dimmable=true, …, dimmer=32768, temperature=4000>
hood.grease_filter      # => #<data Filter threshold=200, hours=50, reached=true>; charcoal_filter too
hood.dehumidification   # also grease_melting, height_position, fan_settable? and auto_refresh_supported?

hood.fan_level = 2         # 0 (off) to 3, 4 for boost, 5 for interval
hood.fan_run_on_time = 15  # 0, 5 or 15 minutes
hood.main_light = true     # and ambient_light=
hood.reset_grease_filter   # and reset_charcoal_filter
hood.wake
```

The reads come from `ExtendedState`, which a hood serves only while it is on: they read nil while
it is off, except an Opcode hood's fan level and light, which come from `State`. A light reports
its dimmer as the hood does, from 0 to 65535.

The app picks each action by protocol, and so does the SDK; a protocol 3 hood drives its fan and
lights as an Opcode one:

| Action | Opcode (1) | Dop1 (2) | DOP2 (3) | DOP2 (4) |
|---|---|---|---|---|
| Fan level, run-on, main light | Oc85, State | Dop1 | Oc85, State | 2/1577, 2/1583 |
| Ambient light | — | Dop1 | — | 2/1583 |
| Filter resets | Oc85 | setting | 2/1583 | 2/1583 |
| Ambient light while cooking, fragrance, auto refresh | — | setting, 1100 | 2/105 | 2/105 |
| Ambient colours, dehumidification, silent blower, grease melting | — | Dop1 | — | — |

The Dop1-only ones are `configure_ambient_light(mode:, rgb:, brightness:, colour_temperature:)`,
`dehumidification =` (`:off` or `:regulated`, the only ones the app writes),
`dehumidification_silent =`, `grease_melting =` and `grease_melting_at(minutes)`; the others are
`ambient_light_while_cooking =`, `fragrance(:start)` (also `:stop` and `:miele_program`) and
`auto_refresh =`.

An action the hood's protocol has not raises `Miele::Sdk::ActionUnavailableError`, and so does one
the hood does not support (ambient light, dehumidification, grease melting, auto refresh,
fragrance), as the app hides it, and the fan while the hood's screen is pushed in, as the app
refuses it. A hood that is off does not say what it supports: those actions ask to `wake` it first. The Opcode fan level goes out twice, half a second apart, as the app sends it. `wake`
writes back the light of a Dop1 or Opcode hood that is off, and sends `DeviceAction` 2 to a DOP2
one, as the app wakes them.

Settings (programming functions, Dop1 object 1201) go out with structure version 1 and Dop1
sections in lower-case hex, as the app sends them. A value out of range raises `ArgumentError`
before anything is sent. `Miele::Sdk::Dop1` builds the requests, and `hood.dop1(request)` sends any
other one; `hood.setting(pf_id)` and `hood.write_setting(pf_id, value)` read and write a setting.

Left out: the ambient light's dimming (the app's conversion is not traced), the auto refresh
schedule, a DOP2 hood's ambient colours, the write that switches a downdraft hood on before its
ambient light, and the ColorFlow switch-off the app's screen sends once a Dop1 hood's ambient light
is off. A DOP2 user request or setting is read and written back, as in the app, with the header the
hood served. None of these writes has been sent to a real hood. The reads have run against a Dop1
hood switched off, serving no `ExtendedState`; Opcode and DOP2 hoods have never been tried.

## Con@ctivity

```ruby
hood.connectivity_plus  # => #<data ConnectivityPlus available=true, activated=false, available_sources=[…], sources=[]>
hood.connect_hob('000111222333')    # and disconnect_hob: Con@ctivity Plus follows the hob
hood.color_flow         # => #<data ColorFlow active=true, interval=10>, nil when the hood has none
hood.configure_color_flow(active: true, interval: 20)  # 5, 10 or 20 seconds
hood.supervise('000111222333', show: true)              # Con@ctivity One
```

Con@ctivity Plus makes a hood follow hobs. As in the app, `connect_hob` and `disconnect_hob` change
one hob in the list `services` shows and switch Con@ctivity Plus on while one is left; the SDK
refuses them unless `services` shows it available, as the app hides it. ColorFlow reads 404, and 500 on a DOP2 hood, as none, and an
interval the app does not know as 10 seconds; the SDK refuses to set it on a hood that has none.
`supervise` writes `SuperVision/{fab}` of the appliance that shows another one, with `Show` alone:
the app leaves `Signal` out. ColorFlow and Con@ctivity Plus have been read from a real hood through
the cloud.

## Hobs

```ruby
hob = Miele::Sdk.appliance('192.0.2.22')
hob.zones            # => [#<data Zone number=1, level=6.0, heat=nil, booster=2, timer=5400, cookware=true, …>]
hob.main_state       # => :running; internal_state names State's InternalState as the app does
hob.minute_minder    # => 130, in seconds
hob.power_doubling?  # and stop_and_go?
hob.temp_control     # => #<data TempControl zone=2, level=:two, target_reached=true, target=120, current=95>
hob.fan              # => #<data Fan level=2, run_on=301>, nil for a hob without one
```

The app only reads a hob: its actions are Cook Assist commands through the Miele cloud, which the
SDK leaves out. Zones follow the app: only those the hob declares, zone 5 in fourth place while it
heats on a four-zone hob, numbered from their controls on a hob that has zone controls, a level in
half steps when the hob doubles its levels, residual heat and keep warm in `heat`, and the end time
as a duration. Two bridged zones side by side share one timer, and `secondary` marks the one the
app's screen hides, except on the hobs whose `ExtendedState` the app pads to 159 bytes. A DOP2 hob
shows zones 1 and 2, as in the app. A hob serves `ExtendedState` only
while it is on; the one tried was off, so the zones have not been read from a real hob.

## Ovens

`Miele::Sdk::Oven` reads and acts as the app's oven module does. Its DOP2 reads come as
[typed objects](#typed-objects):

```ruby
oven.context                # 1/1585: the program, its phase, the requests the oven offers
oven.supported_requests     # => [1, 2, 59], numbered as the app numbers them
oven.program_context        # 1/1574: the selected program and its parameters
oven.target_temperature     # => 180.0 °C, nil when no program sets it; core_target_temperature too
oven.notifications          # 1/131: infos, messages, errors, queries; 1/392 with second_cavity: true
oven.program_groups         # 1/1599: the programs the oven offers
oven.own_programs           # 1/109, along the app's chain of instances
oven.program_steps          # the running own program (2/213) and its steps (2/214)
oven.second_cavity_context  # 1/391, a double oven's second cavity
```

A Dop1 oven (`ProtocolVersion` 2) gives its readings in `state.extended_state`.

```ruby
oven.select_program(13)          # a GLOBAL_EnumPrgId value, or its symbol
oven.target_temperature = 180    # °C
oven.duration = 1800             # seconds
oven.start_at = :now             # or a Time; end_at= takes a Time
oven.set_options(pre_heating: true, keep_warm: true)
oven.start                       # an automatic program: start(at: time), now by default
oven.stop
oven.acknowledge(:query, 4, option: 12)  # or query.id and one of query.ack_options
```

The other parameters are `core_target_temperature=`, `moisture=`, `grill_level=`,
`microwave_power=`, `browning=`, `doneness=`, `steam_bursts=` and `steam_burst_times=` (up to three
times in seconds), and the other requests `continue_cooking`, `steam_burst` and
`stop_keeping_warm`.

Each of these actions makes the checks the app's rules make before it, and raises
`Miele::Sdk::ActionUnavailableError` without sending anything when one fails:

- A Dop1 oven only stops, through `ProcessAction` 2, and only during a function, own or automatic
  program.
- Selecting a program needs remote control without local control. The app's rule that also weighs
  the oven's state has not been traced to the selection, so the SDK leaves it to the oven.
- A parameter needs remote control without local control and a program on the oven, and a mobile
  start too once the program has started (waiting, running, paused or ended) or for program 361.
  `duration = 0` first moves the start to its minimum, as the app does.
- `start` refuses a program that requires a duration not set yet. It first writes the parameters
  the program requires and the user has not confirmed, with the values they show, then sends
  request 1, or 113 when the oven does not offer 1. An automatic program starts by writing its
  start time instead; another program takes `start_at=` beforehand, and `start(at:)` raises
  `ArgumentError` for it.
- `stop` needs one of requests 2, 55, 56 and 57 offered, no pyrolysis abort running, and remote
  control without local control. A program not started yet takes 2, a started one the first of
  55, 56 and 57 the oven offers, started as the app derives its oven state.
- `continue_cooking` needs the oven to offer it (baking or cooking), `steam_burst` request 59
  offered, and `stop_keeping_warm` message 20 shown.
- A double oven's second cavity takes no action but `acknowledge(…, second_cavity: true)`.

The app then waits until the oven shows the change; the SDK returns once the oven accepts the
write, and `program_context` or `notifications` show what follows. Three app behaviours rest on
that wait and are left out: the switch-off that answers queries 4, 5, 21 and 27 as they appear,
the raise of doneness or browning by one step after `continue_cooking` (write it with `doneness=`
or `browning=`), and the required parameters written once a selected program shows (`start`
writes them). None of these writes has been sent to a real oven: their bytes follow the app's
code, and the reads have run against a real oven through the cloud.

## Dishwashers

`Miele::Sdk::Dishwasher` reads and acts as the app's dishwasher module does. It has never been
tested on an appliance: every read and write follows the app's code.

```ruby
dishwasher.context             # 2/1585 at idx 0/1; program_context, programs, notifications
dishwasher.supported_requests  # => [:start, :stop, :start_delay], the app's names; none on a PG81
dishwasher.setting(20_052)     # 2/105 at an SF id, here AutoDos
dishwasher.locked?             # a DOP2 dishwasher its owner locked (RemoteEnable 7)
dishwasher.consumption         # Dop1: #<data Consumption energy=0.8, water=9.4>, in the app's units
dishwasher.consumables         # the Consumables resource; statistics and latest_program_runs on DOP2
dishwasher.program_list        # Dop1 8905; selection reads 8907
```

```ruby
dishwasher.select_program(28)
dishwasher.set_extras(:express, :dry)       # the extras this model's app writes; ArgumentError for others
dishwasher.start                            # or start_delayed(time): today's or tomorrow's time of day
dishwasher.pause                            # resume, stop, cancel
dishwasher.power_on                         # and power_off, on DOP2
dishwasher.auto_dos = true                  # write_setting(id, value) on a G38, G58, G7 or PFD10
dishwasher.acknowledge(info: 700, option: 1)
dishwasher.leave_abort                      # DOP2
dishwasher.open_door                        # Dop1, under mobile start with the door closed
```

Each action makes the checks of the app's rule for it and raises `ActionUnavailableError` without
sending anything when one fails. `start` needs mobile start (and AppSupport bit 4 on DOP2), the door
closed, request 1 offered and the dishwasher ready (Status 3, or 4 awake); `pause` and `resume` need
mobile start and a running or paused program; `stop` needs no mobile start, only a program that
runs, pauses or waits awake, stop or cancel offered, and a dishwasher not locked; `cancel` follows
the app's details bar, where it is the second button only while neither pause nor stop comes
first, from Status 3 to 6, under mobile start, while a program runs or pauses, or while one waits
under remote control (the bar's other Cancel, which reverts the selected extras, is left out);
`start_delayed` needs a program selected (Status 3) under mobile start, the dishwasher not locked. A
DOP2 dishwasher refuses while it shows info 700. A Dop1 dishwasher takes `ProcessAction` on its
`State`, as the app's DeviceStateDto keeps it, its program and extras on 8906 and its delayed start
on 8909. Delays are counted on the wall clock, as the app counts them, so on the day the clocks
change they follow the clock.

Not traced, so left to the dishwasher: where a Dop1 dishwasher shows info 700, and the units of the
Dop1 consumption. The app sends the steps of `power_on` and `power_off` again while it watches
`State` for 15 s; the SDK sends each once.

## Laundry

`Miele::Sdk::WashingMachine` (washing machines and washer-dryers) and `Miele::Sdk::TumbleDryer` read
and act as the app's laundry module does. They have never been tested on an appliance: every read
and write follows the app's code.

```ruby
washer.context             # 2/1585, read without an index: door, process state, requests listed
washer.supported_requests  # => [1, 8], after the app's SupportedRequestsRule
washer.program_context     # 2/1574; notifications (2/131) and anti_crease (2/105) too
washer.programs            # 2/1584, page by page as the app reads it
washer.door                # => :locked; a dryer shows a closed door as locked, as the app does
washer.readings            # Dop1: #<data Reading load=2, soiling=4, …, temperature=40, spin_speed=1400>
washer.program_list        # Dop1 8200, a dryer's 8600; selection reads 8202 or 8601
washer.twin_dos            # the TwinDos trays from services
```

```ruby
washer.select_program(28)
washer.set_parameters(temperature: 40, eco: true, spin_speed: 1400, extras: %i[intensive])
dryer.set_parameters(drying_level: :cupboard_dry, drying_time: 90, extras: %i[anti_crease])
washer.start_delayed(Time.new(2026, 11, 1, 6, 30))   # today's or tomorrow's time of day
washer.start                                         # pause, stop
washer.stop_end_signal                               # 28; stop_to_edit 12102, extend_anti_crease 12144
washer.acknowledge(message: 3, option: 1)
washer.power_off                                     # wake
washer.anti_crease = 2
washer.twin_dos_levels = [{ number: 1, percent: 50 }]
```

The requests follow the app's SupportedRequestsRule: without remote control only stop, no stop while
a program waits (Status 2 or 3), start only with the door locked, request 8 only while 2/1574 shows a
start mode, and nothing while the appliance sleeps deeply. A Dop1 appliance offers start under
remote control (Status 4, or 3 under mobile start without a start time), stop while it waits or
runs (Status 4 or 5), and never pause; it takes `ProcessAction` alone. `stop_to_edit` also needs a program waiting for its
start time, `power_off` a DOP2 program done (Status 7, process state 10 or 13) outside phases 264,
519 and 531, and `wake` a DOP2 model the app wakes (its series letter, from some software id up)
sleeping deeply.

`set_parameters` needs a program selected (Status 3) under mobile start. A washer takes
`temperature` (°C, with `eco`), `spin_speed` (rpm), `soiling`, `cap`, `extras`, `stains`,
`twin_dos`, and on DOP2 `drying_level`, `drying_time` and `program_mode`, or on Dop1 `master_care`;
a dryer takes `extras`, `drying_level` and `drying_time`. On DOP2 the SDK first copies into 2/1577
the current values 2/1574 shows, as the app does, then writes the parameters given; it writes only
members 2/1577 carries. On Dop1 it reads 8201 or 8602 and writes it back with the read request type
and the app's encodings (a temperature it has no code for goes out as 0, an eco 40 °C as 39), and
`NotAcceptedError` reports an Ack other than 1. `start_delayed` lets the appliance choose the mode
as the app does: whole minutes from a minute before now, or local seconds since 1970, both on the
wall clock, then request 8; a Dop1 appliance takes `StartTime`, its selection written back, then
`ProcessAction` 1.

Left out: requests 12106 (add laundry) and 12116 (TwinDos care), which the app declares and never
sends; its limit of three anti-crease extensions; its start time kept until start, for which
`start_delayed` needs start or request 8 offered. An Opcode appliance selects no program, as in
the app, and the SDK sends it no parameters, which the app would send it as DOP2. A tumble dryer of
device type 4 takes the dryer's objects (8602, `selection_para_td`), where the app's parameter copy
and Dop1 delayed start send it the washer's.

Not traced: the order of the bits behind the Dop1 `washing`, `drying` and `eco` readings; the care
phase the app's screen waits for before it offers 12144; and the values a WMV96 shows from 8202
(its capsule dosing among them), which `readings` leaves to `selection`.

## Coffee makers

`Miele::Sdk::CoffeeMaker` reads and acts as the app's coffee module does. It has never been tested
on an appliance: every read and write follows the app's code.

```ruby
coffee.variant           # => :cva_ref2; :cm7, :cm6f, :cva, :cva6000 or :unknown, as the app tells them apart
coffee.program_context   # 1574 at 0/1, on unit 2 for a CM7 and 1 for the others; context (0/8), notifications
coffee.combi_state       # 2/1586
coffee.cleaning          # 2/289; descaling, features, device_ident; nil on a CM7
coffee.profiles          # 1/109 from the standard profile 24812 along the chain, by id; none on a CM7
coffee.drink(24_005)     # 2/261 at idx1 = the drink's id; drink_limits(24_005) reads 2/331
coffee.device_state      # a CVA6000's Dop1 1000; usage_counters reads 8D00
```

```ruby
coffee.brew(24_005, two_cups: true)   # double_shot: true too
coffee.start_barista
coffee.stop
coffee.acknowledge(:query, 3, option: 2)   # :information or :query with its id; the others the option alone
coffee.power_on                            # and power_off
coffee.light = true                        # a CVA6000 only
coffee.create_profile('Anna')              # rename_profile, delete_profile
coffee.edit_drink(24_037, amount: 50, temperature: 2, pre_brewing: 1, bean_sort: 2)
coffee.rename_drink(24_037, 'Mein Kaffee')
```

A DOP2 coffee maker writes 2/1586 as read to switch on and off, waking first when it answers 500,
and its other objects as the app's ModifyDop2Message does: back where they were read, the index
read at as the header's attribute. A CVA6000 takes Dop1 1101 to switch on and off and 1100 to
stop, and its light by writing back its `State` as the app's DeviceStateDto keeps it. `brew` follows the app's drink rule: mobile
start, no information or query shown, no drink, Barista or care program running; two cups or a
double shot also need the software ids the app requires. `start_barista` follows the app's Barista
entry: a CM6F, CVA or Ref2 that lists it among the special beverages of 1/1599, on under remote
control without local control, no program running and no information shown. `delete_profile` needs
coffee profiles in 2/348, and only custom profiles are renamed or deleted. A CM7 takes no profile,
drink or Barista action, and a CVA6000 brews nothing and acknowledges nothing, as in the app.

Left out: tasting, saving a tasted drink, and resetting a drink or a profile, whose values the app
derives through helpers not traced; the message check of the app's Barista start page; the drink tables that limit two cups or a double shot to some
drinks; and the waits the app keeps after switching on or off. The CVA6000's switch-off ignores the
information its dashboard checks.

## Cooling appliances

`Miele::Sdk::CoolingAppliance` (fridges, freezers and wine units) reads and acts as the app's
refrigeration module does. It has never been tested on an appliance: every read and write follows
the app's code. Protocols 200 (BSH), 201 and 203 (Liebherr) serve the JSON `Cooling` resource, an
Opcode appliance (0 and 1) its zones in `State`.

```ruby
fridge.zones             # => [#<data Zone number=1, position=1, rank=1, type=:fridge, temperature=5.0, target=4.0, …>]
fridge.temperature_unit  # => :celsius or :fahrenheit
fridge.modes             # => { eco: #<data Mode on=false, editable=true>, … }
fridge.alarms            # => [:dust_filter], filters and the ice maker at 3, demo mode at 1
fridge.ice_maker         # light, perfect_fresh, humidity, door_alarm_delay (seconds); cooling for the rest
```

```ruby
zone = fridge.zones.first
fridge.set_target(zone, 4)        # whole degrees in the appliance's unit, as the app's picker offers
fridge.set_super_mode(zone, true) # set_fan, set_vario_cool
fridge.set_mode(:eco, true)       # :party, :holiday, :sabbath, :child_proof
fridge.ice_maker = false          # light=, ambient_light_mode=, presentation_light=, humidity=,
                                  # perfect_fresh=, humidifier=, door_alarm_delay=
```

The app reads no zone while the appliance is off and shows no zone temperature on protocol 200.
It addresses a zone's target and super mode by its number, its fan by its position and VarioCool
and presentation light by its rank. On protocol 201 the super mode first gets a duration of 720,
whatever that write answers, then waits 500 ms. An Opcode appliance takes its target through
`Oc85`, in whole °C, and its super mode as `ProcessAction` on `State/ProcessAction`. The app reads
no `RemoteEnable` and checks nothing before these writes; the SDK refuses what the app shows no
control for, such as an ice maker the appliance lacks or a mode it lists no values for, and a
`State` member such as `State/ProcessAction` goes to the cloud on its own.

The SDK sends only what the app's pickers offer, and raises `ArgumentError` for anything else. A
zone's target is one of its `TargetTemp` `AllValues`, else `Min` to `Max` by `Step`, else its
current value, each in whole degrees rounded half away from zero as the app shows them. An Opcode
zone keeps to the app's fixed ranges: 2 to 9 °C for a fridge, -28 to -14 °C for a freezer and 5 to
20 °C for a wine zone; 3 to 9 and -26 to -15 °C on a KFN 37692 iDE or K 3.473 iD; any zone
-28 to -15 °C on an FN 30402 i or FN 35402 i; and only its current target in a zone of no known
kind. PerfectFresh, the humidifier and the door alarm delay keep to `Min` to `Max` by `Step`.
PerfectFresh is refused on protocol 201 and without a `Step`, where the app shows none. The zone
controls (target, fan, VarioCool and presentation light intensity) are refused while the app hides
the zones: off (Status 1, 10 or 255), or on, running or super freezing in Holiday or Sabbath mode
without a door signal. The super mode is refused only while off, as the app's dashboard still
offers it in those modes.

Left out: the app's retries of an Opcode target and its waits after some writes; the screen rule
that hides zone controls during a failure without a failure alarm, as the SDK reads no zone alarm;
and typed reads of zone alarms, target ranges and the ambient and presentation light state, which
`cooling` gives raw. Not traced: whether an appliance serves `Cooling`, `Oc85` and the `State`
members locally, what `10000617000` and the duration of 720 mean, and how a °F appliance reports
its temperatures.

## Warming drawers

`Miele::Sdk::WarmingDrawer` reads and acts as the app's drawer module does. It has never been
tested on an appliance: every read and write follows the app's code.

```ruby
drawer.drawer_state          # => :programmed; an open door shows over off, on, running and paused
drawer.programs              # Dop1 9788: #<data Program id=1, min_hours=1, max_hours=4, temperatures=[30, …]>
drawer.power_on              # from off, finished or idle; power_off from the other states: Dop1 1101
drawer.select_program(1)     # 1 cups, 2 plates, 3 food, 4 low-temperature cooking: Dop1 9781
drawer.target_temperature = 70
drawer.remaining_time = 135  # minutes, from the program's minimum, kept to its maximum; 0 resets it
drawer.cups_warm_up_source = '000111111111'   # a coffee maker the drawer lists; nil to stop
```

Each action makes the check of the app's rule for it. Switching on needs mobile start without local
control and the drawer off, off with its door open, finished or idle, where the app's switch shows
off; switching off the same control and the drawer in any other state but not connected; a program
needs remote control and mobile start without local control, the drawer on, running or off; a
temperature mobile start without local control and one of the program's five steps; a remaining
time remote control and mobile start without local control while the program is set or runs
(Status 3 to 6), and 0 or at least the program's minimum hours, as the app's picker offers. A
temperature re-sends the remaining time, and a remaining time the target, as the app writes them.
`NotAcceptedError` reports an Ack other than 1.

Left out: the cup warm-up's check that its source is a coffee maker by its ident, Con@ctivity One
machines, and typed reads of the drawer's temperatures and times, which `State` gives raw.

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
- `modify(klass, address) { |value| value.with(…) }` reads an object, lets the block change it and
  writes it back with the header the appliance answered, as the app's dishwasher and laundry modules
  do.
- A Dop1 object decodes its sections, bit fields and byte order (`from(bytes)`), and `to_bytes`
  gives what a write section sends.
- `state.extended_state` decodes `ExtendedState` into the object the app builds from it: the hood's
  by `ProtocolVersion` (1 to 4), the Dop1 and Opcode hob's, and the Dop1 oven's. It is nil for the
  other families, which read it otherwise, and when the appliance serves none, as they do switched
  off.

Only the objects the app's family modules use are generated: 402 DOP2 classes, 468 Dop1 classes and
336 enums from the app 4.19.0. Three have been read from an appliance through the cloud, the oven's
`GlobalDeviceContext`, `GlobalPsContext` and `GlobalNtfctnShow`; the hood and hob tried served an
empty `ExtendedState`, being off.

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

The cloud channel has run against the live cloud with a French account: the CIAM code exchange, the
saved token, the account's appliances, their states, the household key, and the DOP2 leaves of an
oven that serves none locally. The token's renewal and MCS logins have not run yet.

## Events

```ruby
hosts = Miele::Sdk.discover.map(&:host)

Miele::Sdk.events(hosts:) do |event|
  puts "#{event.source} #{event.fab} #{event.resource}: #{event.content}"
end
```

`Miele::Sdk.events` follows the appliances at `hosts` on the local network and, when an account is
set, the account's appliances through the Miele cloud, as the app does. It blocks and yields a
`Miele::Sdk::Events::Event` (`fab`, `resource`, `content`, `source`) per change, on the calling
thread: `source` is `:local` for an appliance's push and `:cloud` for the cloud's, and a change
both push arrives twice, once from each. Pass `cloud: nil` to listen only locally; without `hosts`
it listens only to the cloud, and without either it raises `ArgumentError`. When one side fails,
the stream ends with its error. Each side is read on a thread of its own, so a slow block holds back
neither its reads nor the cloud's keep-alive: the events wait for the block in a queue.

`event.attributes` reads `content` as a typed value: a `DeviceIdentification` for `/Ident/`, a
`DeviceState` for `/State/`, of which `/State/Light/` and `/State/Status/` fill only `light` or
`status`, and nil for what only the cloud pushes. Without a block `events` returns a lazy
enumerator: iterate it with `each`, `first` or `take`, since an external `next` never reaches the
end of the stream and leaves the subscriptions in place.

### On the local network

`Miele::Sdk.events(hosts:)` announces this host over mDNS as a peer of the household, listens on
`listener_port`, and asks each appliance to push its changes to it: it declares this host in the
appliance's `SuperVision` and subscribes to `/State/`, `/State/Light/`, `/State/Status/` and
`/Ident/`.

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

### Through the cloud

With an account, `events` opens the cloud's websocket (`/websocket/V2/Devices/` on the account's
REST host) with the session's token and, on every connection, reads the `State` of each of the
account's appliances, as the app does. It then yields what the cloud pushes: `/State/` and
`/Ident/` as JSON, a DOP2 leaf as a `Dop2::Leaf` under `/DOP2/{unit}/{attribute}/`, and the
account's device list, one entry per Wi-Fi module, under `/Devices/` with a nil `fab`. It skips
the other resources. A module without a fabrication number is named by its `mac-…` id.

Each message is acknowledged as the app does, a keep-alive goes out every 30 s, and the websocket
reconnects 6 s after an error or a close, and at once after a minute without a message, each time
with the session's current token, renewed when the cloud refuses it. An account the cloud refuses
ends the stream with `AuthenticationError`. A frame that stops halfway counts as silence: when the
minute runs out, it reconnects at once, as the app's library does. A handshake that stalls gives up
after a minute. It connects directly, without the environment's proxy.

It has run against the live cloud with a French account. The cloud pushes its messages as `POST`
requests behind a `CloudConnect: sc-data-…` header, the device list first, then `State` changes;
the SDK reads neither the method nor the header, which it echoes in its acknowledgement. No
`Ident` or DOP2 push has been seen yet.

### Polling

The app reads again every 3 s the DOP2 leaves the cloud does not push. `Miele::Sdk.poll` does the
same with a typed object, until the block breaks:

```ruby
Miele::Sdk.poll(oven, Miele::Sdk::Objects::Oven::GlobalOpProgramInfoCA, [2, 213, 0, 1]) do |steps|
  puts steps.amount_of_steps
end
```

It yields the object on the first read and each time it changes, and reads it again `every:`
seconds (3 by default) after each read ends. A failed read ends the poll with its error.

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
| `Miele::Sdk::ActionUnavailableError` | a check the app makes before an action fails: nothing is sent |
| `Miele::Sdk::NotAcceptedError` | a Dop1 appliance acknowledges a write with anything but success |
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
