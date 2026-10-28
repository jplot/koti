# Cloud schemas and SIA codes

The cloud schemas in `lib/ajax/sdk/cloud/schemas/` and the SIA event labels in
`lib/ajax/sdk/sia/codes.tsv` come from outside the gem. `extract/` rebuilds them; the gem itself
does not use it.

## Where they come from

- **Cloud schemas.** The Ajax app for Android (`com.ajaxsystems` 3.59) talks to its cloud over gRPC
  with protobuf classes generated in its Java code. Each generated file carries its descriptor as a
  string literal, and each gRPC stub names its service, its methods with their call types, and the
  classes of their requests and responses, mostly obfuscated. `descriptors.pb.gz` holds every
  descriptor as a `FileDescriptorSet`; `methods.tsv` each method with its request and response
  messages.
- **Pairing.** A class goes by its full Java name, from the imports or the package of the file that
  names it. Its own descriptor pins its file and its field numbers pick the message there, a
  top-level one when they leave several. Else a readable `*Request` or `*Response` class gives its
  message by name, and an obfuscated one by its field numbers in the service's package. A method
  without a class takes the messages of its name (`arm` takes `ArmRequest`), of its service's
  (`LoginByPasswordService` takes `LoginByPasswordRequest`), or the package's lone request and
  response. From the app 3.59, 608 methods are paired and 1 is not.
- **SIA codes.** [pysiaalarm](https://github.com/eavanvalkenburg/pysiaalarm) (commit `c445c15`)
  lists the codes in `src/pysiaalarm/data/sia_codes.py`, read as text.

## Rebuilding

1. Decompile the app's `base.apk` with [jadx](https://github.com/skylot/jadx) 1.5.6 and `--no-res`.
   The files above come from three runs with `--show-bad-code`, over its `classes18.dex` and
   `classes26.dex` to `classes31.dex`, over its other `classes*.dex` and over the whole APK, and a
   fourth without it, over `classes12.dex` alone.
2. Rebuild the cloud schemas from the `sources/` directory of every run, in any order; the methods
   left unpaired are listed on stderr:

   ```sh
   bundle exec ruby schema/extract/schemas.rb path/to/jadx-*/sources --out lib/ajax/sdk/cloud/schemas
   ```

3. Rebuild the SIA codes from a pysiaalarm checkout:

   ```sh
   bundle exec ruby schema/extract/sia_codes.rb path/to/pysiaalarm/src/pysiaalarm/data/sia_codes.py \
     lib/ajax/sdk/sia/codes.tsv
   ```

From the app and the pysiaalarm commit above, they write the same `methods.tsv` and `codes.tsv`, and
a `descriptors.pb.gz` holding the same bytes once decompressed: the gzip header carries the time of
the run.
