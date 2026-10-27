# Typed values

`hue.json` describes every typed value of `Hue::Sdk::Schema`; `generate.rb` turns it into
`lib/hue/sdk/schema/*.rb` and `sig/hue/sdk/schema/*.rbs`. Neither the gem nor its specs read the
description at run time, but a spec fails while the generated files differ from it.

## Contents

- `resources`: for each resource type, its response class and, when the Hue app sends one, its
  update and create request classes.
- `classes`: each class with the app class it comes from, its kind (`response`, `update` or `add`)
  and its fields, in the order of the bridge's JSON. A field has a type (`String`, `Integer`,
  `Numeric`, `Boolean`, `Hash` for free-form JSON, a class, or a list of either), whether it is
  required, and for a string enum the values known.

## Where it comes from

- **Classes and types.** The Hue app for Android, version 6.3.2 (build 26247, Flutter 3.47,
  Dart 3.13.7), builds and parses this JSON with classes generated from the API description:
  `*Added` for a resource the bridge reports, `*Update` and `*Add` for the requests it sends. Its
  Dart snapshot was decompiled with [blutter](https://github.com/worawit/blutter) (with the
  single-snapshot support of its pull request 213, without code analysis). The JSON keys and types
  of a response come from the `fromJson` of its class; those of a request from its `toJson`, a key
  written without a null check being required.
- **What the app leaves out.** An AOT build drops the classes the app never uses: there is a
  request class for 18 types to update and 8 to create, and a request class only holds the fields
  the app sends.
- **Always present.** The app reads every response field as nullable. A response field is required
  here when [aiohue](https://github.com/home-assistant-libs/aiohue) (commit `e12e5a7`) requires it
  too and a bridge sent it in every resource it reported; a request field when both the app and
  aiohue require it. The enum values come from aiohue as well.
- **Check.** Every resource of a Bridge Pro (BSB003, software 6.3.2071556020) parses against these
  classes; the only key they lack is `type` in the `dependees` of a `behavior_instance`.

## Regenerating

Edit `hue.json`, then:

```sh
bundle exec rake schema
```

Reading a newer version of the app takes the app itself and blutter, so it is not part of the
repository.
