# Lommepenge app

The family's app for tasks and pocket money. Parents create tasks with an
amount, the children mark them as done, and the parents approve – in the app
or directly from a notification in Home Assistant.

**Home Assistant is the server.** The integration in the same repository
(`custom_components/lommepenge`) stores the family's data, calculates
deadlines and restrictions, and is the only place the app talks to. The app
has no server of its own and needs no internet – only the home network.

## Languages

English (default), Danish, German, Spanish and French. The app asks for the
language on first start (English is preselected); it can be changed later
under *Settings* in parent mode, on the connect screen and on the child's
tablet. The phone's own language is never used. The app sends its language
to Home Assistant, so error messages from HA come back in the same language.

Amounts are shown in the currency chosen in Home Assistant (free text, `DKK`
by default).

The texts are in `lib/l10n/app_<language>.arb`; `app_en.arb` is the template.
Flutter generates `lib/l10n/app_localizations*.dart` from them
(`flutter gen-l10n`, also run by `flutter pub get`).

## Roles

The role is chosen in Home Assistant when the device is added, and cannot be
changed on the device itself:

| Role | View | Parent part |
| --- | --- | --- |
| Family screen (e.g. the fridge) | All children, one column per child | Locked with the family's PIN |
| Parent's phone | Shared task list and balances | Locked with the family's PIN |
| Child's tablet | Only that child's tasks | Does not exist – HA refuses anything other than "mark as done" for the child itself |

The PIN is set in Home Assistant. A child's tablet can only be connected again
after a reinstall (`allowBackup="false"`).

## Installing on a new device

1. In Home Assistant: *Lommepenge → Add device*. Choose a name and role (and
   child). HA shows a code and a link to a page with a QR code.
2. Install the app (**Download the app** on the page from HA), open it and
   choose the language.
3. Enter the code and tap **Connect** – or scan the QR code if the device has
   a camera. On Android the page also has **Open the app and connect**.

## Updates

App and integration are released together: a tag `vX.Y.Z` builds a signed
APK with GitHub Actions (`.github/workflows/release.yml` in the repository
root) and puts it on the release together with its SHA-256. Home Assistant
fetches it from there, and the app shows "New version ... is ready".
**Update** downloads the APK from HA, checks the SHA-256 and asks Android to
install it. The version code is `major·10000 + minor·100 + patch`.

## Signing

The app is signed with a fixed key (`lommepenge-release.jks`), which is kept
outside git together with `key.properties`. GitHub Actions gets it via the
secrets `KEYSTORE_BASE64` and `KEYSTORE_PASSWORD`. **If the key is lost, no
device can be updated without a reinstall** – keep a backup.

Without `android/key.properties` the build uses the debug key (for
`flutter run`).

## Development

```bash
flutter pub get
flutter test
flutter build apk --release --target-platform android-arm,android-arm64
```

See `WINDOWS_SETUP.md` for Flutter on Windows.

## Structure

```
lib/
  main.dart                  router: language → connect → the role's home screen
  l10n/                      translations (ARB) and helpers (l10n.dart)
  providers/app_state.dart   state, language, sync with HA, offline queue, updates
  services/ha_client.dart    signed requests to the integration
  services/native_bridge.dart  links, version, installation (MainActivity.kt)
  repositories/              local copy of the family's data and the same rules as HA
  logic/                     availability, deadlines and restriction
  screens/ widgets/          UI
```
