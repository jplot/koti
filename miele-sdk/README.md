# miele-sdk

Unofficial Ruby SDK for Miele@home appliances. It talks to them on the local network with the
household key, or through the Miele cloud when given the account's, as the Miele app does once an
appliance is paired.

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
app and by the appliances. The Miele account gives the GroupID and the GroupKey, as it gives them
to the app: `Miele::Sdk.cloud.group` reads them from the cloud (`/V2/GroupKeyId/`). The SDK signs
only with the `group_id` and `group_key` set, and raises `ConfigurationError` without them (for
`events`, under the `failures` of a `SubscriptionError`). Keep the key secret: it controls every
appliance of the household.

```ruby
group_id, group_key = Miele::Sdk.cloud.group   # with the account configured, see Cloud
Miele::Sdk.configure do |config|
  config.group_id = group_id
  config.group_key = group_key
end
```

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
500 as done, as the app does. Both belong to `Miele::Sdk::Oven` and raise
`Miele::Sdk::ActionUnavailableError` on a Dop1 oven, whose protocol has no such leaf. They send in
any other state: `power_on_offered?` tells whether the app's offline screen offers the switch-on
(remote control or mobile start, and no H2 oven), and `power_off_offered?` whether its settings
switch offers the switch-off (remote control without local control, or mobile start alone, and an
oven that is connected, `Status` other than 255).

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
hood.fan_run_on_time = 15  # minutes; fan_run_on_times gives the app's picker: 0, 5 and 15
hood.main_light = true     # and ambient_light=
hood.reset_grease_filter   # and reset_charcoal_filter
hood.wake                  # wake_offered? tells whether the app would
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
`dehumidification =` (`:off`, `:controlled` or `:regulated`; `dehumidification_modes` gives the
app's picker, without `:controlled`),
`dehumidification_silent =`, `grease_melting =` and `grease_melting_at(minutes)`; the others are
`ambient_light_while_cooking =`, `fragrance(:start)` (also `:stop` and `:miele_program`) and
`auto_refresh =`.

An action the hood's protocol has no request for raises `Miele::Sdk::ActionUnavailableError` (the
dashes above). Every other action is sent as given, even one the app hides or refuses: the
readings give the app's rules, so the client's screen can follow them. The app hides what the hood
does not support (`lights.ambient.exists`, `dehumidification.supported`,
`grease_melting.supported`, `auto_refresh_supported?`, `fragrance_supported?`), and refuses the fan
while the hood's screen is pushed in (`fan_settable?` false). A hood that is off does not say what
it supports: those readings are nil until it is woken. The Opcode fan level goes out twice, half a
second apart, as the app sends it. `wake` writes back the light of a Dop1 or Opcode hood, and sends
`DeviceAction` 2 to a DOP2 one; the app wakes a Dop1 or Opcode hood only while it is off
(`wake_offered?`).

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
hood.configure_color_flow(active: true, interval: 20)  # color_flow_intervals: 5, 10 and 20 seconds
hood.supervise('000111222333', show: true)              # Con@ctivity One
```

Con@ctivity Plus makes a hood follow hobs. As in the app, `connect_hob` and `disconnect_hob` change
one hob in the list `services` shows and switch Con@ctivity Plus on while one is left; the app
hides them unless `connectivity_plus.available`, and the SDK sends them all the same. ColorFlow
reads a 404 through the cloud, and a 500 on a DOP2 hood, as none, and an interval the app does not
know as 10 seconds; `configure_color_flow` sends any interval to any hood, where the app sets one
of its three on a hood whose `color_flow` is not nil, and a 404 raises `NotFoundError`.
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
oven.select_program_offered?     # => true where the app enables its program selection
oven.select_program(13)          # a GLOBAL_EnumPrgId value, or its symbol
oven.parameter_editable?(:target_temperature)  # => true where the app lets it change
oven.target_temperature = 180    # °C, truncated to hundredths as the app does: 37.3 writes 3729
oven.duration = 1800             # seconds
oven.start_at = :now             # or a Time; end_at= takes a Time
oven.set_options(pre_heating: true, keep_warm: true)
oven.start                       # an automatic program: start(at: time), now by default
oven.stop
oven.acknowledge(:query, 4, option: 12)  # or query.id and one of query.ack_options
```

The other parameters are `core_target_temperature=`, `moisture=`, `grill_level=`,
`microwave_power=`, `browning=` and `doneness=`, and the other requests `continue_cooking`,
`steam_burst` and `stop_keeping_warm`. The SDK sets no steam burst count or time: the app 4.19.0
never enables its cells for them, so it never writes either. `microwave_power=` writes the bit it is
given; `microwave_powers` gives those the app's picker offers: 0x01 to 0x40 for 80 to 1000 W (steps
1 to 7 on an oven of `ContinentVariant` 2), among those set in
`program_context.context_para_ca.mw_power.supported_bits`. When the oven answers 500 to the write,
the SDK reads 1/131 every 3 seconds, as the app does, and takes the write as done if info 14 shows
within the app's 6 seconds; otherwise it raises the 500.

Every action sends what it is given, whatever the app's screens would offer: the client decides,
and the predicates below give it the app's rule for each, read as the app reads it. An action
raises `Miele::Sdk::ActionUnavailableError` without sending anything only when there is nothing
to send: on a Dop1 oven, which only stops (through `ProcessAction` 2), for a parameter with no
program selected on 1/1574 (no ProgId to write), and for `start` when 1/1574 lacks one of the
parameters the app reads before writing any. A value its wire type does not hold raises
`ArgumentError`.

| Predicate | The app's rule |
|---|---|
| `power_on_offered?`, `power_off_offered?` | see [Commands](#commands) |
| `select_program_offered?` | DetermineIsProgramWriteable: remote control without local control, an oven neither off nor running nor waiting to start, no program on 1/1585 (ProgId 0), and no query 16011 or 16013 on 1/131 |
| `parameter_shown?(name)` | the section the app shows: none while 1/131 shows message 20 or 19 (keep warm or rapid cooling running after the program); a value readable on 1/1574 (request mask 8); for all but browning and doneness, a function on 1/1585 (program type 2, 3, 4, 5, 7, 8, 38 or 50) that 1/1574 shows too (ShouldHideProgramParameters); a current target temperature above zero; no duration or start time while the oven runs or pauses with a duration set; no start or end time while a readable duration is unset |
| `parameter_editable?(name)` | the section shown, remote control without local control and a program on the oven, mobile start too once the program has started (waiting, running, paused or ended) or for program 361, and the cell enabled: a writable value (request mask 1), and mobile start for browning and doneness and for the duration, start and end times of an own or automatic program |
| `option_shown?(name)`, `option_editable?(name)` | that function and the option readable; to change it, the parameters allowed as above, the option writable, and mobile start for an automatic program's options |
| `start_offered?` | a program selected (a ProgId on 1/1574), automatic, or with a duration set where it requires one |
| `stop_offered?` | one of requests 2, 55, 56 and 57 offered, no pyrolysis abort running, and remote control without local control; on a Dop1 oven, a function, own or automatic program |
| `continue_cooking_offered?` | the continue bubble and button: the oven offering it (baking or cooking), a finished program (OvenState End) other than a cleaning, no keep warm or rapid cooling running after it, and mobile start under remote control without local control |
| `stop_keeping_warm_offered?` | message 20 shown |
| `steam_burst_offered?` | request 59 offered for a REST `ProgramID`, a manual steam burst (`NumberOfSteamBursts` readable, 1 to 3) in a function 1/1585 and 1/1574 both show, the oven running or paused, and a burst left, or the last one under way (`BitField` 16); every value the app reads for the button must be there, the three steam burst times and `BitField` among them |

A parameter takes the names of its setter (`:target_temperature`, `:duration`…), an option those
of `set_options` (`:keep_warm`…). `duration = 0` first moves the start to its minimum, as the app
does.

- Selecting a program reads 1/1574 every 3 seconds until it shows the program, as the app does,
  retrying a read refused with other than a 4xx after 1.5^n seconds (the n-th in a row), and
  writes the parameters the program requires, as `start` does. Where the app only logs it, the
  first refusal of those raises once the program is selected, and so does a parameter missing
  from 1/1574, as an `ActionFailedError`. When 1/1574 has not shown the program within the app's
  15 seconds, it raises `Miele::Sdk::ActionFailedError` and writes no parameter.
- `start` first writes the parameters the program requires and the user has not confirmed, with
  the values they show, a temperature through degrees and back as the app does (3730 writes
  3729), then sends request 1, or 113 when the oven does not offer 1. Like the app, it writes
  every one of them though one is refused, then raises the first refusal without starting. The
  app reads all eight it may write (temperature, core temperature, moisture, grill level,
  microwave power, duration, browning, doneness) before writing any: when 1/1574 lacks one,
  `start` writes none and raises `Miele::Sdk::ActionUnavailableError`, and a selection writes
  none. An automatic program starts by writing its start time instead; another program takes
  `start_at=` beforehand, and `start(at:)` raises `ArgumentError` for it, request 1 carrying no
  time.
- `stop` sends request 2 for a program not started yet, and for a started one the first of 55, 56
  and 57 the oven offers, else 2, started as the app derives its oven state.
- `continue_cooking` then reads 1/1585 every 3 seconds, as the app does, until the oven asks for
  a cooking level (ProgPhase 10000) or cooks on (heating or remaining time, 28100, 28114, 28115 or
  28124). Asked, it reads 1/1574 every 3 seconds until it shows a doneness the oven requires and
  lets write, else such a browning, and writes it one step higher (255 becomes 0, as the app
  writes a byte), without the checks of the cooking level cells, then waits for the oven to cook
  on. Past the app's 15 seconds it raises `Miele::Sdk::ActionFailedError`, and so it does at once
  when 1/1585 shows no program phase or 1/1574 lacks the doneness, browning or ProgId the app
  reads.
- A double oven's second cavity takes no action but `acknowledge(…, second_cavity: true)`.

The app then waits until the oven shows the change; but for a selection, the SDK returns once the
oven accepts the write, and `program_context` or `notifications` show what follows. One app
behaviour rests on that wait and is left out: the switch-off that answers queries 4, 5, 21 and 27
as they appear. None of these writes has been sent to a real oven: their bytes follow
the app's code, and the reads have run against a real oven through the cloud.

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
dishwasher.set_extras(:express, :dry)       # offered_extras gives those the app writes on this model
dishwasher.start_offered?                   # => true where the app's start rule allows it
dishwasher.start                            # or start_delayed(time): today's or tomorrow's time of day
dishwasher.pause                            # resume, stop, cancel
dishwasher.power_on                         # and power_off, on DOP2
dishwasher.auto_dos = true                  # write_setting(id, value); offered_settings for this model
dishwasher.acknowledge(info: 700, option: 1)
dishwasher.leave_abort                      # DOP2
dishwasher.open_door                        # Dop1, under mobile start with the door closed
```

Each action sends what it is given; a predicate gives the app's rule for it, so the client's screen
can offer what the app's would. An action raises `ActionUnavailableError`, sending nothing, only
where the dishwasher's protocol has no address for it. A Dop1 dishwasher has no DOP2 leaf:
`power_on`, `power_off` and `leave_abort` (2/1586), `acknowledge` (2/138), `write_setting` and
`auto_dos=` (2/105) raise on it. A DOP2 dishwasher has no Dop1 object 1404: `open_door` raises on
it. `set_extras` raises `ArgumentError` for an extra the dishwasher's object has no place for (a
member `GLOBAL_PS_ExtrasDW` lacks, a name without a bit on 8906); it sets the model's extras on or
off as named, and another one named on.

| Predicate | The app's rule |
|---|---|
| `start_offered?` | mobile start (and AppSupport bit 4 on DOP2), the door closed, request 1 offered and the dishwasher `ready?` (Status 3, or 4 awake) |
| `pause_offered?`, `resume_offered?` | mobile start and a running (pause offered) or paused (start offered) program |
| `stop_offered?` | no mobile start needed: a program that runs, pauses or waits awake, stop or cancel offered, and a dishwasher not locked |
| `cancel_offered?` | the details bar (`details_bar?`: Status 3 to 6, not asleep waiting to start, not locked), where cancel is the second button only while neither pause nor stop comes first, under mobile start, while a program runs or pauses, or while one waits under remote control; the bar's other Cancel, which reverts the selected extras, is left out |
| `start_delayed_offered?` | a program selected (Status 3) under mobile start, the dishwasher not locked |
| `power_on_offered?`, `power_off_offered?` | DOP2, remote control, and the dishwasher off (Status 1, or 4 asleep) or on and not locked |
| `leave_abort_offered?` | DOP2 under remote control |
| `open_door_offered?` | Dop1, waiting for its program (Status 2 or 3) under mobile start with the door closed |

`start_offered?`, `pause_offered?`, `resume_offered?`, `stop_offered?` and `cancel_offered?` are
false while a DOP2 dishwasher shows info 700. A Dop1 dishwasher takes `ProcessAction` on its
`State`, as the app's DeviceStateDto keeps it, its program and extras on 8906 and its delayed start
on 8909. Delays are counted on the wall clock, as the app counts them, so on the day the clocks
change they follow the clock.

Not traced, so left to the dishwasher: where a Dop1 dishwasher shows info 700, and the units of the
Dop1 consumption. The app sends the steps of `power_on` and `power_off` again while it watches
`State` for 15 s; the SDK sends each once. As the app's SwitchOnForDop2Action, `power_on` writes
2/1586 only while `State` shows Status 1 or 4, which it reads again after waking the dishwasher, and
writes nothing otherwise.

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
washer.power_off                                     # power_off_offered? gives the app's rule; wake too
washer.anti_crease = 2
washer.twin_dos_levels = [{ number: 1, percent: 50 }]
```

Each action sends what it is given; the client decides, with the app's rules at hand.
`supported_requests` gives the requests the app's SupportedRequestsRule offers (start, stop, pause,
12102, 12144…): without remote control only stop, no stop while a program waits (Status 2 or 3),
start only with the door locked, request 8 only while 2/1574 shows a start mode, and nothing while
the appliance sleeps deeply. A Dop1 appliance offers start under remote control (Status 4, or 3
under mobile start without a start time), stop while it waits or runs (Status 4 or 5), and never
pause; it takes `ProcessAction` alone, pause as 3. The other rules come as predicates:

| Predicate | The app's rule |
|---|---|
| `stop_end_signal_offered?` | a DOP2 appliance listing request 28 on 2/1585 |
| `stop_to_edit_offered?` | a program waiting for its start time (Status 4), request 12102 offered |
| `power_off_offered?` | a DOP2 program done (Status 7, process state 10 or 13) outside phases 264, 519 and 531 |
| `wake_offered?` | a DOP2 model the app wakes (its series letter, from some software id up) sleeping deeply |
| `set_parameters_offered?` | a program selected (Status 3) under mobile start, on DOP2 or Dop1 |
| `start_delayed_offered?` | start or request 8 offered |

`stop_end_signal`, `stop_to_edit`, `extend_anti_crease`, `power_off` and `anti_crease=` raise
`Miele::Sdk::ActionUnavailableError` on a Dop1 or Opcode appliance, whose protocol has no DOP2 leaf
to write them to (`ProcessAction` has no value for requests 28, 12102 and 12144); so do
`select_program`, `set_parameters` and `start_delayed` on an Opcode appliance, which has no
selection object. A washer takes `temperature` (°C, with `eco`), `spin_speed` (rpm), `soiling`,
`cap`, `master_care`, `extras`, `stains`, `twin_dos`, and on DOP2 `drying_level`, `drying_time` and
`program_mode`; a dryer takes `extras`, `drying_level` and `drying_time`. On DOP2 an extra is any
member of `GLOBAL_PS_ExtrasWM` or `GLOBAL_PS_ExtrasTD`: those the app writes are set on when named
and off otherwise, another named is set on, each where 2/1577 carries it. Another parameter, or a
name the object has no place for, raises `ArgumentError`. On DOP2 the SDK first copies into 2/1577
the current values 2/1574 shows, as the app does, then writes the parameters given; it writes only
members 2/1577 carries. On Dop1 it reads 8201 or 8602 and writes it back with the read request type
and the app's encodings (a temperature it has no code for goes out as 0, an eco 40 °C as 39, and the
TwinDos containers only when given both), and `NotAcceptedError` reports an Ack other than 1.
`start_delayed` lets the appliance choose the mode as the app does: whole minutes from a minute
before now, or local seconds since 1970, both on the wall clock, then request 8; a Dop1 appliance
takes `StartTime`, its selection written back, then `ProcessAction` 1.

Left out: requests 12106 (add laundry) and 12116 (TwinDos care), which the app declares and never
sends; its limit of three anti-crease extensions; its start time kept until start. The SDK sends
an Opcode appliance no parameters, which the app would send it as DOP2. A tumble dryer of
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
coffee.brew_offered?                  # => true where the app's drink rule allows a drink
coffee.brew(24_005, two_cups: true)   # double_shot: true too
coffee.start_barista                  # barista_entry? gives the app's rule
coffee.stop                           # drink_stoppable? gives the app's rule
coffee.acknowledge(:query, 3, option: 2)   # :information or :query with its id; the others the option alone
coffee.power_on                            # and power_off
coffee.light = true                        # a CVA6000's; light_offered? gives the app's rule
coffee.create_profile('Anna')              # rename_profile, delete_profile
coffee.edit_drink(24_037, amount: 50, temperature: 2, pre_brewing: 1, bean_sort: 2)  # drink_settings: the pickers
coffee.rename_drink(24_037, 'Mein Kaffee')
```

A DOP2 coffee maker writes 2/1586 as read to switch on and off, waking first when it answers 500,
and its other objects as the app's ModifyDop2Message does: back where they were read, the index
read at as the header's attribute. A CVA6000 takes Dop1 1101 to switch on and off and 1100 to
stop, and its light by writing back its `State` as the app's DeviceStateDto keeps it.

Every action sends what it is given; the predicates give the app's rules, so the client's screen
can offer what the app's dashboard would:

| Predicate | The app's rule |
|---|---|
| `power_on_offered?`, `power_off_offered?` | the power switch: a known variant off (Status 1), or on (2 or 3) with no Barista running, under remote control without local control; a CVA6000 off, or on, paused, ended, failed or cancelled, under its remote control |
| `light_offered?` | a CVA6000 neither disconnected, locked nor in service |
| `drink_stoppable?` | the stop button: a drink running, not cancelled, no care program, under remote control without local control; a CVA6000 running a drink (Status 5) |
| `brew_offered?` | the drink rule: the program info read in full, mobile start, no information or query shown, no drink, Barista or care program running |
| `one_touch?` | two cups or a double shot: the software ids the app requires |
| `barista_entry?` | a CM6F, CVA or Ref2 that lists Barista among the special beverages of 1/1599, on under remote control without local control, no program running and no information shown |
| `profile_name_allowed?(id, name)` | a custom profile (`custom_profiles`), a name neither blank, another profile's nor Miele |
| `delete_profile_offered?(id)` | a custom profile, coffee profiles listed in 2/348 |
| `drink_name_allowed?(id, name)` | a CVA, a drink outside the standard profile, a name not blank |

As the app's SwitchOnHelper, `power_on` writes nothing, and does not wait, once 2/1586 shows
ApplianceState 4. An action raises `Miele::Sdk::ActionUnavailableError` only where nothing can be
written: `brew`, `start_barista` and `acknowledge` on a CVA6000, which has no DOP2 leaf for them;
`light=` on a DOP2 coffee maker, for which the app has no light request (its DOP2 light action sends
nothing); `power_on` and `power_off` on a coffee maker neither DOP2 nor Dop1; the profile and drink
actions on a CM7 or CVA6000, which have no such object; `create_profile` once the app's slots are
used (4 on a CM6160, 8 on another CM6F, 10 otherwise). `brew` takes a program id the app defines,
not 0, and acknowledgements options 1 to 17, 1 to 16 on a CM7, as the app's mappers do; another
raises `ArgumentError`, and so does a drink value its 2/261 member does not hold. `edit_drink`
writes 255 as the bean sort on all but a CVA, as the app does.

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
fridge.target_choices(zone)       # => [2, 3, 4, 5, 6], the whole degrees the app's picker offers
fridge.set_target(zone, 4)        # degrees in the appliance's unit
fridge.zones_shown?               # => true where the app shows the zone controls
fridge.set_super_mode(zone, true) # set_fan, set_vario_cool
fridge.set_mode(:eco, true)       # :party, :holiday, :sabbath, :child_proof
fridge.ice_maker = false          # light=, ambient_light_mode=, presentation_light=, humidity=,
                                  # perfect_fresh=, humidifier=, door_alarm_delay=
fridge.ice_maker_offered?         # each setting has its _offered? predicate, and its picker its _choices
```

The app reads no zone while the appliance is off and shows no zone temperature on protocol 200.
It addresses a zone's target and super mode by its number, its fan by its position and VarioCool
and presentation light by its rank. On protocol 201 the super mode first gets a duration of 720,
whatever that write answers, then waits 500 ms. An Opcode appliance takes its target through
`Oc85`, in whole °C as 16-bit two's complement, and its super mode as `ProcessAction` on
`State/ProcessAction`; the Cooling API takes a target in hundredths. As the app, the SDK sends
nothing for a zone's current target.

The app reads no `RemoteEnable` and checks nothing before these writes but the controls its
screens show; the SDK sends what it is given, and the predicates and pickers below give the app's
rules. An Opcode target that is not whole degrees in 16 bits (a whole Float such as 5.0 is) raises
`ArgumentError` before anything is read. An Opcode appliance has no `Cooling` resource: `set_fan`,
`set_vario_cool`, `set_mode` and the settings written there (`ice_maker=`, `presentation_light=`,
`set_presentation_light_intensity`, `humidity=`, `perfect_fresh=`, `humidifier=`,
`door_alarm_delay=`) raise `ActionUnavailableError` on it, and so does `ambient_light_mode=` on a
protocol but 200 and 203, which has no such setting. An unknown mode or humidity name raises
`KeyError`.

`target_choices(zone)` gives what the app's target picker offers: the zone's `TargetTemp`
`AllValues`, else `Min` to `Max` by `Step`, else its current value, each in whole degrees rounded
half away from zero as the app shows them. An Opcode zone offers the app's fixed ranges: 2 to 9 °C
for a fridge, -28 to -14 °C for a freezer and 5 to 20 °C for a wine zone; 3 to 9 and -26 to -15 °C
on a KFN 37692 iDE or K 3.473 iD; any zone -28 to -15 °C on an FN 30402 i or FN 35402 i; and only
its current target in a zone of no known kind. `perfect_fresh_choices`, `humidifier_choices`,
`door_alarm_delay_choices` and `humidity_choices` give `Min` to `Max` by `Step`;
`ambient_light_choices` the BSH ambient light modes numbered from 1 in their picker's order, or a
Liebherr one's 1 to 7; `presentation_light_intensity_choices` 0 (off) and 1 to 7.

| Predicate | The app's rule |
|---|---|
| `zones_shown?` | the zone controls (target, fan for a zone with one, VarioCool for a zone with it): hidden while off (Status 1, 10 or 255); while on, running or super freezing without a door signal, in Holiday or Sabbath mode; and in a failure without a door alarm, unless Holiday or Sabbath is on. A failure alarm shows the zones in both cases: the ice maker's alarm, a zone's power failure, or a temperature alarm in a freezer zone or a wine zone the app counts as one |
| `super_mode_offered?(zone)` | a zone with a super mode, the appliance not shown off: the dashboard still offers it in those modes |
| `modes[name].editable` | a mode the appliance lists values for |
| `ice_maker_offered?` | an appliance with an ice maker, not at Status 1 or 255, `IceMaker` 1, 2 or 3 |
| `perfect_fresh_offered?` | not at Status 1 or 255, not on protocol 201, with a `Step` |
| `humidifier_offered?`, `door_alarm_delay_offered?` | not at Status 1 or 255, the setting listed at a `Value` but -1 |
| `settings_shown?` | not at Status 1 or 255, not in a failure without a door signal, not in Holiday or Sabbath mode |
| `humidity_offered?` | a KWTUS or Rioja wine unit, `settings_shown?`, a `HumidityControl` value other than -1 |
| `presentation_light_intensity_offered?` | a KWTUS or Rioja wine unit with a presentation light, `settings_shown?`, a light state (`PresentationLight` at 1 or 2) |
| `light_shown?`, `light_offered?` | a wine unit the app lights (no Rioja), with a light state (`AmbientLightState`, or `Light` in `State`, at 1 or 2, or no `Light` in `State`), where the zones show or the dashboard's quick action does: at any Status but 1, 10 or 255, in Holiday or Sabbath mode only under a failure, filter or door alarm, or with Party or Eco mode on |
| `presentation_light_offered?` | the presenter light section or the same quick action, with a light state |
| `ambient_light_offered?` | a BSH wine unit, or a protocol 203 one neither KWTUS nor Rioja, where the zones show, with the light on and its setting listed |

Left out: the app's retries of an Opcode target and its waits after some writes, and typed reads of
zone alarms, target ranges and the ambient and presentation light state, which `cooling` gives
raw. Not traced: whether an appliance serves `Cooling`, `Oc85` and the `State`
members locally, what `10000617000` and the duration of 720 mean, and how a °F appliance reports
its temperatures.

## Warming drawers

`Miele::Sdk::WarmingDrawer` reads and acts as the app's drawer module does. It has never been
tested on an appliance: every read and write follows the app's code.

```ruby
drawer.drawer_state          # => :programmed; an open door shows over off, on, running and paused
drawer.programs              # Dop1 9788: #<data Program id=1, min_hours=1, max_hours=4, temperatures=[30, …]>
drawer.power_on              # Dop1 1101; power_off too
drawer.select_program(1)     # 1 cups, 2 plates, 3 food, 4 low-temperature cooking, 0 off: Dop1 9781
drawer.target_temperature = 70
drawer.remaining_time = 135  # minutes; 0 resets it
drawer.cups_warm_up_source = '000111111111'   # a coffee maker's fab; nil to stop
```

Each action sends what it is given; the predicates give the rule the app enables it by, and
`programs` its pickers (the five temperature steps and the minimum and maximum hours of each
program), `cups_warm_up` the coffee makers it lists.

| Predicate | The app's rule |
|---|---|
| `switchable?` | mobile start without local control, which every rule below needs |
| `power_on_offered?` | the drawer off, off with its door open, finished or idle, where the app's switch shows off |
| `power_off_offered?` | the drawer in any state but off, off with its door open, finished or not connected, idle included |
| `select_program_offered?` | remote control too, the drawer on, running or off |
| `target_temperature_offered?` | a program |
| `remaining_time_offered?` | remote control too, the program set or running (Status 3 to 6); the picker offers 0, or the program's minimum to maximum hours |
| `cups_warm_up_offered?` | the drawer connected and `cups_warm_up` available |

`select_program` takes any program `Betriebsart` defines, 0 (Aus) included, where the app's
picker offers 1 to 4, and raises `ArgumentError` for another; a temperature raises it for degrees
its byte does not hold, and a remaining time when negative. A temperature and a remaining time
raise `ActionUnavailableError` while `State` shows no program 1 to 4, Betriebsart 0 being Aus. A
temperature re-sends the remaining time, and a remaining time the target, as the app writes them;
the maximum hours of `programs` are the app's picker, not a limit on the write.
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
- An attribute the leaf lacks reads nil, and so does an enum, a struct or an array of either whose
  wire type does not fit, as the app fails that one attribute. `write_object` writes back the
  attributes as read, each changed member in the wire type it was read in, and raises
  `ArgumentError` for a member it did not read, as the app's setters do.
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
`cloud_token` or an existing `token_file`), `Miele::Sdk.cloud` opens its cloud, and an appliance given
that cloud is reached through it. A cloud built from the copy the app bundles, when the locales did not
answer, is not kept: the next call asks them again.

```ruby
Miele::Sdk.configure do |config|
  config.country = 'FR'
  config.token_file = File.expand_path('~/.config/koti/miele-token.json')
  config.ciam_client_id = ENV.fetch('MIELE_CIAM_CLIENT_ID')  # CIAM countries
  config.email = ENV.fetch('MIELE_EMAIL')                     # MCS countries
  config.password = ENV.fetch('MIELE_PASSWORD')
end

Miele::Sdk.appliances                      # the account's appliances, reached locally by their module's name
ovens = Miele::Sdk.appliances(through_cloud: true).grep(Miele::Sdk::Oven)
ovens.first.dop2(1, 1585)                  # through the cloud, as the app reads it
```

**Which way.** An appliance sends every request locally, and a resource its module does not serve
raises `NotFoundError`. Given a cloud (`Appliance.for(host, fab:, cloud:)`, or `through_cloud: true`),
it sends every request under `/Devices/` there instead, under `/V2`; a Dop1 request names the module
in `Host`, as the app does: for Dop1, `host` is then the module's name as the cloud lists it
(`Miele::Sdk.cloud.devices`), which `through_cloud: true` gives. The module's own resources
(`info`, `host_info`, `software_update`) have no counterpart in the cloud and are still read from
the module. Which way to reach an appliance is the caller's. A hood's ColorFlow reads a 404 as none
only through the cloud, as the app does.

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

A request the cloud answers 401 raises `ResponseError` and keeps the token, as the app's appliance
client does. The appliance list is handled as the app handles a lost session: a 401 or 403 on
`devices` (and so on `Miele::Sdk.appliances`) logs the account out, at `/V2/Logout` or the CIAM
logout address, forgets the token and deletes `token_file`, then raises `ResponseError`. The next
request logs in again with `email` and `password`, or raises `ConfigurationError` until a new CIAM
code is exchanged; a `cloud_token` setting is left as given. A renewal the cloud refuses (a 401, or a
CIAM `invalid_grant`) ends the session the same way and raises `AuthenticationError`.

`ciam_client_id` is the Miele app's OAuth client id (`MA.Constants.CdcKeys.ClientId` in
`Miele.Modules.Authentication`); the gem does not ship it. The cloud client follows the
environment's proxy settings; the local one never does.

The cloud channel has run against the live cloud with a French account: the CIAM code exchange, the
saved token, the account's appliances, their states, the household key, and the DOP2 leaves of an
oven that serves none locally. The token's renewal, MCS logins and the logout have not run yet.

## Events

```ruby
hosts = Miele::Sdk.discover.map(&:host)

Miele::Sdk.events(hosts:, cloud: Miele::Sdk.cloud) do |event|
  puts "#{event.source} #{event.fab} #{event.resource}: #{event.content}"
end
```

`Miele::Sdk.events` follows the appliances at `hosts` on the local network and, given `cloud:`
(`Miele::Sdk.cloud`), the account's appliances through the Miele cloud, as the app does. It blocks
and yields a `Miele::Sdk::Events::Event` (`fab`, `resource`, `content`, `source`) per change, on the
calling thread: `source` is `:local` for an appliance's push and `:cloud` for the cloud's, and a
change both push arrives twice, once from each. Without `cloud:` it listens only locally; without
`hosts` it listens only to the cloud, and without either it raises `ArgumentError`. When one side
fails, the stream ends with its error. Each side is read on a thread of its own, so a slow block
holds back neither its reads nor the cloud's keep-alive: the events wait for the block in a queue.

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

When the block breaks or raises, the subscriptions are deleted and `SuperVision` stops showing this
host; the peer entry itself stays listed. An appliance that cannot be reached at that point keeps
its subscriptions, and `events` raises a `Miele::Sdk::SubscriptionError` naming each such host
(`failures`, by host) once the others are withdrawn, unless an error already ended the stream; the
next run deletes them, since `listener_fab` does not change. An appliance that cannot be enrolled
raises a `SubscriptionError` naming it, once the others are withdrawn.

Every push must be signed with the household key, or it is answered 403. The date a push carries is
not checked: a push captured on the network can be sent again.

The appliances must reach `listener_port` on this host and resolve its name over mDNS. When they
sit on a network of their own (an IoT VLAN), allow TCP from that network to this host's
`listener_port` and relay mDNS between the two networks. Set `advertise_address` when the host has
several network interfaces.

Enrollment and withdrawal have run against real appliances, leaving their subscriptions as they
were. Pushes from a real hood and a real hob, which has no `SuperVision`, have been received,
verified and decoded. A real oven accepted the same subscriptions and never pushed, not even while
heating; follow such an appliance by reading its `state` at intervals.

### Through the cloud

Given `cloud:`, `events` opens the cloud's websocket (`/websocket/V2/Devices/` on the account's
REST host) with the session's token and, on every connection, reads the `State` of each of the
account's appliances, as the app does. It then yields what the cloud pushes: `/State/` and
`/Ident/` as JSON, a DOP2 leaf as a `Dop2::Leaf` under `/DOP2/{unit}/{attribute}/`, and the
account's device list, one entry per Wi-Fi module, under `/Devices/` with a nil `fab`. The app
reads no other resource from the websocket; the SDK yields them all the same, as JSON where they
parse and as pushed otherwise, and a push outside any appliance under its own path with a nil
`fab`. A module without a fabrication number is named by its `mac-…` id.

Each message is acknowledged as the app does, a keep-alive goes out every 30 s, and the websocket
reconnects 6 s after an error or a close, and at once after a minute without a message, each time
with the session's current token, which a refused handshake does not renew, as in the app. An
account the cloud refuses ends the stream with `AuthenticationError`. A frame that stops halfway
counts as silence: when the
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
| `Miele::Sdk::AuthenticationError` | the appliance refuses a read: the key does not match its own; or the cloud refuses the account or its renewal |
| `Miele::Sdk::ResponseError` | the appliance answers with an error status; carries `status` |
| `Miele::Sdk::NotFoundError` | the appliance does not serve that resource, or the GroupID is not its own (a `ResponseError`) |
| `Miele::Sdk::RemoteControlDisabledError` | the appliance refuses a command (a `ResponseError`) |
| `Miele::Sdk::ActionUnavailableError` | the appliance's protocol or state gives no request to send for the action: nothing is sent |
| `Miele::Sdk::NotAcceptedError` | a Dop1 appliance acknowledges a write with anything but success |
| `Miele::Sdk::ActionFailedError` | an appliance takes an action's write but does not show its effect within the app's 15 seconds |
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
