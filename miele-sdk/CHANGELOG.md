# Changelog

All notable changes to this gem are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Breaking:** where the Miele app sends an action's requests with the action's token, which its
  Timeout cancels, each request gets only what that Timeout has left, and none goes out once it has
  run out: `ActionFailedError` is raised instead, as it is, with the `ConnectionError` as cause, by
  a request that times out as that Timeout runs out. That holds for a rename and Con@ctivity One
  and Plus (15 s), a cooling appliance's `set_mode` (5 s), a DOP2 dishwasher's `power_on`, its
  wake step and its switch step each, and its `power_off` (15 s each, `State` read and three
  attempts included), a DOP2 coffee maker's `power_on` (45 s) and `power_off` (15 s), and an
  oven's actions (15 s, 45 s for `power_on`), but for the start reset before a zero duration,
  which the app sends with its caller's token: only the duration write after it is refused. Through
  the cloud, a login or a token renewal counts in that time: `Cloud::Channel#request` takes a block
  that gives the timeout once its token is in hand. A coffee maker's `power_on` counts its 45 s from
  before its `State` read, and an oven's `select_program` and `continue_cooking` their 15 s from
  before their write, as the app's Timeouts do; an oven's `select_program` writes the required
  parameters after them, with no bound of their own. A 500 on the 1/1574 read of an oven's
  `microwave_power=` is taken as one on its write, which the app sends under the same action.
- Requests the app sends under a token of their own wait no longer than it gives them: a DOP2
  dishwasher's reads and writes 15 s, its 2/1574 read 5 s before a delayed start or ProfiLine
  extras and 15 s before other extras, and its wake's `State` read and `DeviceAction` 2 15 s each;
  a Dop1 dishwasher's `State` read and write 1 s each to start, pause, resume, stop or cancel, and
  its 8906 read, its extras' `State` read and its door opening 5 s; a laundry appliance's Dop1
  selection read and write 8 s; a CVA6000's 1101 and 1100 15 s; a warming drawer's 1101 and 9781
  5 s. A Dop1 dishwasher's 8906 and 8909 writes keep `read_timeout`: the app sends them with no
  token, under HttpClient's 100 s. `get`, `state`, `dop1` and `object` take that `timeout:`.
- **Breaking:** a write the appliance refuses raises, 400 included, as the Miele app never takes a
  refusal as done: `wake` and a hood's Dop1 writes no longer take a 400 as done, and a hood's Dop1
  writes raise `NotAcceptedError` for an Ack other than 1, but for the ProcessAction of the
  fragrance stop and Miele program, whose Ack the app drops. `wake` reads `State` first where the
  app does: a Dop1 or Opcode hood gets its light written back only while off, and raises
  `NotAcceptedError` unless the answer carries `Success`; a DOP2 hood gets `DeviceAction` 2 only
  while asleep, then `State` is read every half second until it shows the hood awake, raising
  `ActionFailedError` after a minute; a DOP2 dishwasher is woken only off, or waiting to start out
  of `StandbyState` 1, and a Dop1 one raises `ActionUnavailableError`. An oven's `power_on` ends
  with the error of a `DeviceAction` 2 that fails instead of writing again, and a dishwasher's or a
  DOP2 coffee maker's `power_on` raises a refused `DeviceAction` 2, 400 included. A CVA6000's `light=`
  raises `NotAcceptedError` unless the answer's first `Success` carrying `Light` gives back the light
  written, as the app's LightStateAction requires.
- **Breaking:** without `group_id` and `group_key`, the local channel no longer reads the household
  key from the Miele account: it raises `ConfigurationError`. `Miele::Sdk.cloud.group` gives the
  account's key to set them.
- **Breaking:** an appliance no longer turns to the cloud on its own after a local 404: it is reached
  locally, raising `NotFoundError`, unless given a cloud (`Appliance.for(host, fab:, cloud:)` or
  `Miele::Sdk.appliances(through_cloud: true)`), and then every request under `/Devices/` goes
  through it; `through_cloud?` tells which. `Appliance.new` no longer takes `module_host:`: Dop1
  requests through the cloud name `host` in `Host`, which must then be the module's name as
  `Miele::Sdk.cloud.devices` lists it (as `Miele::Sdk.appliances` gives it). A hood's `color_flow`
  and `configure_color_flow` read a 404 as none only through the cloud, and raise it locally.
- **Breaking:** `Oven#select_program` raises, once the program is selected, the first refusal of a
  required parameter, or an `ActionFailedError` for a parameter missing from 1/1574, instead of
  ignoring them.
- **Breaking:** `start`, `stop`, `pause`, `light_on` and `light_off` are gone from `Appliance`: the
  Miele app sends them differently in each family, and they come back that way, ovens first.
- **Breaking:** a hood's `fan_level=` refuses while its screen is pushed in, and asks to `wake` a hood
  that is off; `wake` writes back a Dop1 or Opcode hood's light instead of `DeviceAction` 2, as the
  app does.
- **Breaking:** `Dop1` requests spell their section in lower-case hex, as the app writes them.
- **Breaking:** `Miele::Sdk.appliance` and `Miele::Sdk.appliances` return the class of each
  appliance's family. The hood's `fan_level=`, `fan_run_on_time=`, `main_light=`, `setting` and
  `write_setting` moved to `Hood`, and `power_on` and `power_off` to `Oven`.
- **Breaking:** `remote_control?` follows the app for each family and answers nil where the app
  never reads `RemoteEnable`; `mobile_start?` and `local_control?` join it.
- **Breaking:** `dop2` reads without a query unless given an index, `write_dop2` leaves the
  indexes in the leaf unless given `with_index: true`, and `Dop1.setting_value` takes only the
  hood's answer.
- **Breaking:** `Miele::Sdk.events` takes `cloud:` (`Miele::Sdk.cloud`) to also yield the account's
  events through the cloud. `Event` has a fourth member, `source`.
- **Breaking:** the events listener no longer prints with `warn` and goes on: an appliance it cannot
  enroll, and once the block breaks those it cannot withdraw, raise a `SubscriptionError` whose
  `failures` gives the error of each host; a push whose signature fails is answered 403 and nothing
  else.
- **Breaking:** commands no longer refuse what the Miele app's screens hide or disable, nor a value
  its pickers do not offer: ovens, dishwashers, laundry appliances, hoods, coffee makers, cooling
  appliances and warming drawers send what they are given, and the predicates below give the app's
  rules. `ActionUnavailableError` now means only that the appliance's protocol or state gives no
  request to send (a DOP2 leaf on a Dop1 appliance, a parameter with no program selected…), and
  `ArgumentError` only a value the wire cannot carry. A hood's `dehumidification =` takes
  `:controlled`. A cooling
  appliance's `set_target` takes a fraction of a degree on the Cooling API, and a whole Float on
  Opcode. A warming drawer's `select_program` takes 0 (Aus), its `remaining_time=` is no longer kept
  to the program's maximum, and both its `target_temperature=` and `remaining_time=` raise
  `ActionUnavailableError` while `State` shows no program 1 to 4. A Dop1 dishwasher's `auto_dos=`
  raises `ActionUnavailableError`, having no 2/105. Laundry `set_parameters` writes any extra the
  DOP2 object carries (`starch_hold`, `program_locked`, `fan_clocking`…) and `master_care` on DOP2
  washers. An oven's parameter predicates and `ParameterGates` name a parameter after its setter
  (`:target_temperature`). Where the app sends nothing, neither does the SDK: a coffee maker's
  `power_on` still writes nothing once 2/1586 shows it on, nor its `light=` on DOP2, and a
  dishwasher's `power_on` writes 2/1586 only at Status 1 or 4.
- The cloud event stream yields every resource the cloud pushes, where it skipped those the app does
  not read: as JSON where it parses, else as pushed, and a push outside any appliance under its own
  path.
- **Breaking:** every request, to an appliance or to the Miele cloud, is sent once, as the app sends
  it: a GET, PUT or DELETE whose connection drops before the answer, or whose answer outlasts
  `read_timeout`, raises `ConnectionError` instead of going out a second time.
- **Breaking:** what the app's actions send again on purpose goes out again. After a 5xx or a lost
  connection, never a 4xx nor a request that outlasts `read_timeout`, a laundry appliance's DOP2
  actions send each read and write again 1.5^n s later, 15 s from the seventh time, with no limit,
  as the app's BaseApiAction`1 does: an action the appliance keeps answering 500 no longer raises.
  `name=` does the same within 15 s; an Opcode `set_target` posts again 5 s apart, three attempts
  within 15 s; `supervise`, `connect_hob` and `disconnect_hob` write again 2 s apart, four attempts
  at most, the last two reading `services` again once its last answer is 3 s old, as the app's
  poll keeps it until then. A dishwasher's `power_on` (its wake,
  then 2/1586) and `power_off`, and a DOP2 coffee maker's `power_off`, send each step up to three
  times back to back, whatever fails, a 400 included. A DOP2 coffee maker's `power_on` starts again
  5 s after any failure, three attempts in all, and wakes one that answers 500 every 5 s within
  45 s, a wake's own time counting in its 5 s; an oven's `power_on` wakes it every 3 s until 45 s are
  up instead of giving up after three attempts. These bounds, and those of an oven's waits, run on
  the wall clock, request times included, as the app's Timeouts do: an appliance takes `clock:`, a
  monotonic clock by default.
- **Breaking:** a dishwasher's `power_off`, and a DOP2 coffee maker's `power_off` and `power_on`,
  read `State` first, as the app's ExecuteSequentiallyUntilTrue does, and send nothing while it shows
  the appliance off already (Status 1) or, for the coffee maker's `power_on`, on already (a Status
  other than 1, 8 and 255, or none).
- A laundry action's DOP2 requests wait 8 s at most for their connection and for their answer, and
  the 2/1574 read of `set_parameters` and `start_delayed` 10 s, as the app's tokens bound them; a
  request that runs out of time is not sent again. `Connection.request`, `Cloud::Channel#request`,
  `Cloud::Http.request`, `dop2` and `write_dop2` take that `timeout:`, which `open_timeout` and
  `read_timeout` still cap and which bounds the write too. `set_parameters` and `start_delayed` read
  2/1577 before 2/1574, as the app's SelectParametersAsync does.
- **Breaking:** `supervise`, `connect_hob` and `disconnect_hob` read back what they wrote, as the
  app polls it, every 3 s within its 15 s, write retries included: `SuperVision/{fab}` right after
  the write, `services` 3 s after the answer the write was made from, unless that answer already
  shows it. They raise `ActionFailedError` when it does not show in time.
- **Breaking:** a 401 from the cloud is handled as the app handles it. A request under `/V2` answered
  401 raises `ResponseError` (status 401) instead of going out again with a renewed token, which is
  kept, and the websocket no longer renews a token its handshake is refused with: it connects again
  6 s later with the session's current token. A 401 or 403 on the appliance list
  (`Cloud::Channel#devices`, so `Miele::Sdk.appliances` and the cloud event stream) logs the account
  out and forgets its token, `token_file` included, then raises `AuthenticationError`, which ends the
  stream; the next request logs in again (`Cloud::Session#invalidate`). An MCS logout that cannot
  reach the cloud keeps the token, as the app keeps it. A renewal the cloud refuses (a 401, which an MCS renewal gets twice
  as the app's client sends it once more, or a CIAM 400 `invalid_grant`) does the same and raises
  `AuthenticationError`, instead of logging in again at once.

### Fixed

- A Dop1 write whose answer the app cannot parse (not JSON, no `Response`, a `Response` that is no
  string) raises `NotAcceptedError`, as the app takes it as a failed write, instead of
  `JSON::ParserError`, `KeyError` or `NoMethodError`, or reading the bits of a numeric `Response`
  as an Ack.
- Requests to the account's cloud (`/V2`, MCS login and renewal) name a language (`Accept-Language`),
  without which it answers 500.
- `power_on` and `power_off` send what the app's oven module sends, without the 2/1583 opcode
  fallback taken from ha-miele-at-lan, and `power_off` takes a 500 as done, as the app does.
- Dop1 settings go out with structure version 1, and the README's filter example resets the
  operating hours (40012) instead of writing the filter limit (40010) to 0.
- DOP2 fields of every type the app knows decode and encode; strings lose their trailing NULs.
- The events listener withdraws every appliance, then stops its server and its mDNS announcements,
  even when a withdrawal raises an error other than a `Miele::Sdk::Error`, such as an unreadable
  answer: that error joins the `SubscriptionError` failures, and no longer hides the one that ended
  the stream. An interrupted withdrawal still stops the server and the announcements.
- `Appliance#get` raises a `ResponseError` carrying the status for an answer without a body, instead
  of `JSON::ParserError`, an error outside `Miele::Sdk::Error`.
- MCS logins, renewals and logouts go out as the app's MCS clients send them, as
  `application/json; charset=utf-8` with `Accept: application/json`, the logout with an empty JSON
  object; a DELETE to the cloud without content carries `Content-Length: 0`.

### Added

- The rules of the app's screens and pickers as public predicates and readers, read as the app reads
  them. Ovens: `power_on_offered?`, `power_off_offered?`, `start_offered?`, `stop_offered?`,
  `stop_keeping_warm_offered?`, `steam_burst_offered?`, `continue_cooking_offered?`,
  `select_program_offered?`, `parameter_shown?`, `parameter_editable?`, `option_shown?`,
  `option_editable?` and `microwave_powers`. Dishwashers: `start_offered?`, `pause_offered?`,
  `resume_offered?`, `stop_offered?`, `cancel_offered?`, `leave_abort_offered?`,
  `power_on_offered?`, `power_off_offered?`, `start_delayed_offered?`, `open_door_offered?`,
  `ready?`, `details_bar?`, `offered_extras` and `offered_settings`. Laundry: `stop_end_signal_offered?`,
  `stop_to_edit_offered?`, `wake_offered?`, `power_off_offered?`, `set_parameters_offered?` and
  `start_delayed_offered?`, beside `supported_requests`. Hoods: `fragrance_supported?`,
  `wake_offered?`, `fan_run_on_times`, `color_flow_intervals` and `dehumidification_modes`, beside
  the readings. Coffee makers: `power_on_offered?`, `power_off_offered?`, `light_offered?`,
  `brew_offered?`, `drink_stoppable?`, `barista_entry?`, `one_touch?`, `profile_name_allowed?`,
  `delete_profile_offered?`, `drink_name_allowed?`, `custom_profiles` and `drink_settings`. Cooling
  appliances: `zones_shown?`, `settings_shown?`, `light_shown?`, `super_mode_offered?`,
  `ice_maker_offered?`, `light_offered?`, `ambient_light_offered?`, `presentation_light_offered?`,
  `presentation_light_intensity_offered?`, `humidity_offered?`, `perfect_fresh_offered?`,
  `humidifier_offered?`, `door_alarm_delay_offered?`, `target_choices` and the `*_choices`
  readers of each setting. Warming drawers: `switchable?`, `power_on_offered?`,
  `power_off_offered?`, `select_program_offered?`, `target_temperature_offered?`,
  `remaining_time_offered?` and `cups_warm_up_offered?`.
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
- Dishwashers as the app's dishwasher module drives them, in Dop1 and DOP2: typed reads of the
  device and program contexts, programs, notifications and settings, the Dop1 consumption,
  consumables and statistics; start, pause, resume, stop, cancel, delayed start, program and
  extras, power, AutoDos and settings, answers to infos, leaving the abort state and opening the
  door, each after the checks the app makes. None of it has run against a real dishwasher.
- Washing machines, washer-dryers and tumble dryers as the app's laundry module drives them, in
  Opcode, Dop1 and DOP2: typed reads of the contexts, programs page by page, the door, Dop1
  readings and TwinDos; the user requests after the app's SupportedRequestsRule, program
  selection, parameters, delayed start, answers to messages, power off, wake, the anti-crease
  setting and TwinDos filling levels. None of it has run against a real appliance.
- `NotAcceptedError`, for a Dop1 write the appliance acknowledges with anything but success, or a
  hood's wake or a CVA6000's light answered without the `Success` the app looks for.
- `ActionFailedError`, for an action whose effect the appliance does not show within the app's wait.
- Coffee makers as the app's coffee module drives them: the variant, typed reads of the contexts,
  notifications, cleaning, descaling, features, profiles and drinks, and the CVA6000's Dop1 state;
  switching on and off, brewing a drink for one or two cups and with a double shot, Barista,
  stopping, answers to notifications, the CVA6000's light, profiles and drink settings. None of it
  has run against a real coffee maker.
- Fridges, freezers and wine units as the app's refrigeration module drives them, on the Cooling API
  and Opcode: zones, modes, alarms, ice maker, light, PerfectFresh, humidity and door alarm delay;
  zone targets, super modes, fan, VarioCool, modes, ice maker, lights, humidity, PerfectFresh,
  humidifier and door alarm delay. None of it has run against a real appliance.
- Warming drawers as the app's drawer module drives them: their state, programs and cup warm-up;
  switching on and off, program, temperature and remaining time, and the cup warm-up source. None of
  it has run against a real drawer.
- The account's appliances followed through the Miele cloud's websocket, as the app follows them:
  the `State` of each read again on every connection, then the `State`, `Ident`, DOP2 leaves and
  device list the cloud pushes, each acknowledged, the connection kept alive and reconnected as the
  app does. `Event#source` tells `:local` from `:cloud`, and `Event#attributes` is nil for a DOP2
  leaf or the device list.
- `Miele::Sdk.poll`, which reads a typed object again 3 s after each read ends and yields it each
  time it changes, as the app polls the DOP2 leaves the cloud does not push.

- Typed values of the DOP2 and Dop1 objects the Miele app uses, generated from its classes under
  `Miele::Sdk::Objects::<Family>`: `Appliance#object` and `#write_object` at the addresses the app
  uses, and `State#extended_state` for hoods, hobs and Dop1 ovens.
- The Miele cloud next to the local channel, as the Miele app uses it: the cloud and login system of
  the account's country from the locales the app reads, MCS login or CIAM code exchange, a token
  renewed once across threads and kept in `token_file`, requests under `/V2` for an appliance given
  the cloud, `Miele::Sdk.appliances`, and `Cloud::Channel#group`, the account's household key.

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
