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
  request class for 19 types to update and 8 to create, and a request class only holds the fields
  the app sends.
- **Always present.** The app reads every response field as nullable. A response field is required
  here when [aiohue](https://github.com/home-assistant-libs/aiohue) (commit `e12e5a7`) requires it
  too and a bridge sent it in every resource it reported, and the `id` of a resource always is. A
  request field is required when the app always writes it, unless aiohue lets it be None. The enum
  values come from aiohue as well.
- **Check.** Every resource of a Bridge Pro (BSB003, software 6.3.2071556020) parses against these
  classes; the only key they lack is `type` in the `dependees` of a `behavior_instance`.

## Regenerating

Edit `hue.json`, then:

```sh
bundle exec rake schema
```

## Rebuilding hue.json

`extract/` rebuilds `hue.json` from a newer version of the app. The app, blutter, aiohue and the
capture of a bridge stay out of the repository; the capture holds a home's data. It needs Python
3.9 or later and `llvm-objdump`; Homebrew's `llvm` is keg-only, so set
`LLVM_OBJDUMP=$(brew --prefix llvm)/bin/llvm-objdump`.

1. Take `lib/arm64-v8a/libapp.so` and `libflutter.so` from the app's `split_config.arm64_v8a.apk`.
2. Build [blutter](https://github.com/worawit/blutter) from its pull request 213
   (`git fetch origin pull/213/head`, commit `fe935fd`), which reads Dart 3.13; a newer Dart may
   need a newer blutter. Run it without code analysis:

   ```sh
   python3 blutter.py path/to/arm64-v8a path/to/blutter-output --no-analysis
   ```

3. Capture every resource of a bridge, read-only:

   ```sh
   HUE_HOST=… HUE_BRIDGE_ID=… HUE_APPLICATION_KEY=… bundle exec ruby schema/extract/capture.rb path/to/capture.json
   ```

4. Merge the app's classes, the models of an aiohue checkout and the capture, then regenerate:

   ```sh
   bundle exec ruby schema/extract/build.rb path/to/blutter-output path/to/libapp.so \
     path/to/aiohue/aiohue/v2/models path/to/capture.json > path/to/hue.json
   cp path/to/hue.json schema/hue.json
   bundle exec rake schema
   ```

`build.rb` describes the resource types hue-sdk has a model for in `lib/hue/sdk/models/`: a type
the app adds needs its model first, and a model whose `*Added` class the app lacks stops the build.
From the app, the aiohue commit and the bridge named under *Where it comes from*, it writes this
`hue.json` byte for byte.

On stderr, it lists by kind what to check:

- `response field left untyped`, `request field left untyped`: fields typed `Object`, the app's
  code, and aiohue for a request, giving no type.
- `aiohue requires, live lacks`, `app requires, aiohue does not`: fields left optional.
- `no aiohue class for …`: resource types aiohue does not know. Their response fields are
  optional but the `id`, and their request fields follow the app alone.
- `request type inferred from the response class`, `request type taken from aiohue`: where a
  request field got its type, for information.
