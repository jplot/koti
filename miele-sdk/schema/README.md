# Typed values

The classes of `Miele::Sdk::Schema` are written by hand after the JSON classes of the Miele app for
Android. `extract/` reads those classes from the app, tells whether the typed values still match
them, and finds the app class that reads a resource. The gem itself does not use it.

## Where it comes from

- **The app.** `de.miele.infocontrol` 4.19.0 is .NET for Android. Its assemblies sit in one store,
  `lib/arm64-v8a/libassemblies.arm64-v8a.blob.so` of its `split_config.arm64_v8a.apk`. It reads and
  writes the appliances' JSON with Newtonsoft.Json classes: a field's key is its `JsonProperty`
  (or `JsonPropertyName`) name, or else its property name. `extract/` reads properties only, not public fields, nor those
  of a base class or a nested class: the classes below have none of them, but for the base class
  of `CheckUpdateResponseBodyDto`, of which only `ReleaseNotes` is used.
- **The classes.** Each typed value follows one app class, listed in `extract/check.rb`;
  `ModuleUpdateInfo` also takes `ReleaseNotes` from a second one:

  | Typed value | App class | Assembly |
  |---|---|---|
  | `DeviceIdentification`, `DeviceIdentificationLabel`, `XkmIdentificationLabel`, `DeviceState` | `…Rest.DeviceIdentificationDto`, `…LabelDto`, `…XkmIdentificationLabelDto`, `…DeviceStateDto` | `Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols` |
  | `SuperVision`, `SuperVisionDevice` | `…Dtos.SuperVisionDto`, `…SuperVisionDeviceDto` | `Miele.Modules.Conactivity.ApplianceCommunication.Implementation` |
  | `Subscription` | `…Dtos.SubscriptionDto` | `Miele.Libraries.ApplianceCommunication.RawCommunication` |
  | `ModuleUpdateInfo` | `…ModuleUpdateInfoDto`, and `…CheckUpdateResponseBodyDto` for `ReleaseNotes` | `Miele.Modules.RemoteUpdate`, `Miele.Modules.Pairing` |

- **Optional members.** A member may be nil where the app's field may be null: a `Nullable` value
  type, or a reference the C# nullable annotations let be null. `ReleaseNotes` only exists in the
  class the app reads the same answer with over Bluetooth, so the Wi-Fi answer may lack it.
- **No class.** The app has none for `Settings`, `Service`, the appliance's `Update`, `/Info` or
  `/Host`: they stay hashes.

## Locales

`lib/miele/sdk/cloud/locales.json` is the copy of the countries' clouds the app bundles, reduced to
what a login needs: each organization's code, countries, REST host and CIAM switch and endpoints.
Its feature settings, API keys among them, stay out. To refresh it from a newer app:

```sh
monodis --mresources path/to/dlls/Miele.Libraries.Foundation.Platform.dll
ruby schema/extract/locales.rb \
  Miele.Libraries.Foundation.Platform.Locales.SalesCompanies.Repository.Bundled.LocalesJson.Production.json \
  lib/miele/sdk/cloud/locales.json
```

## Checking a newer version of the app

It takes `ikdasm`, which comes with Mono (`monodis` fails on some of the app's assemblies).

1. Unpack the assemblies of the store:

   ```sh
   bundle exec ruby schema/extract/assembly_store.rb path/to/libassemblies.arm64-v8a.blob.so path/to/dlls
   ```

2. Print the IL of the five assemblies above:

   ```sh
   for name in Libraries.ApplianceCommunication.Implementation.ApplianceProtocols \
               Libraries.ApplianceCommunication.RawCommunication \
               Modules.Conactivity.ApplianceCommunication.Implementation Modules.Pairing Modules.RemoteUpdate; do
     ikdasm path/to/dlls/Miele.$name.dll > path/to/il/Miele.$name.il
   done
   ```

3. Compare the typed values with their app classes:

   ```sh
   bundle exec ruby schema/extract/check.rb path/to/il
   ```

   It lists each key the app adds or drops, each member whose optionality differs from the app's,
   a class gathering the keys it does not declare on one side only, and each app class it no
   longer finds, and exits with 1 when there is one. For the app 4.19.0 it lists none.

4. To find the app class that reads a resource, capture every resource of the appliances,
   read-only, then rank the app classes holding the most of each resource's keys. Printing the IL of
   every `Miele.*.dll` widens the search. The capture holds the home's data: keep it out of the
   repository.

   ```sh
   MIELE_GROUP_ID=… MIELE_GROUP_KEY=… MIELE_HOSTS=host,… bundle exec ruby schema/extract/capture.rb path/to/capture.json
   bundle exec ruby schema/extract/match.rb path/to/il path/to/capture.json
   ```
