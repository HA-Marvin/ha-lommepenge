# Building the APK on your own Windows PC

Releases are built by GitHub Actions (see `README.md`), so you only need this
to build and test the app yourself. The first time typically takes 30-60
minutes (mostly download time) and only has to be done once – after that a
new APK builds in a few minutes.

## 1. Install Android Studio (incl. the Android SDK)
1. Download Android Studio from https://developer.android.com/studio
2. Run the installer with the default choices. It also installs the Android
   SDK and an emulator.
3. Open Android Studio once and go through the setup wizard (it downloads the
   last SDK components).

## 2. Install the Flutter SDK
1. Download Flutter for Windows from https://docs.flutter.dev/get-started/install/windows
2. Unpack the zip file to e.g. `C:\src\flutter` (avoid paths with spaces or
   `Program Files`).
3. Add `C:\src\flutter\bin` to your PATH:
   - Search for "Edit environment variables for your account" in Windows
     search.
   - Under "User variables" → select `Path` → "Edit" → "New" → paste
     `C:\src\flutter\bin`.
4. Open a **new** Command Prompt/PowerShell and run:
   ```
   flutter doctor
   ```
   Follow its instructions (e.g. accept the Android licences with
   `flutter doctor --android-licenses`) until the Android part is green ✅.
   (The Chrome/VS Code items are not needed to build an APK.)

## 3. Build the app
1. Open a terminal in the repository's `app` folder.
2. Run:
   ```
   flutter pub get
   flutter analyze
   flutter test
   flutter build apk --debug
   ```
   `flutter pub get` also generates the translations in `lib/l10n/`.
3. When the build succeeds, the APK is here:
   ```
   build\app\outputs\flutter-apk\app-debug.apk
   ```

## 4. Install on a device
See "Installing on a new device" in `README.md`. A debug build cannot be
installed on top of the release-signed app from Home Assistant – uninstall
that first, or build with the release key (see "Signing" in `README.md`).

---
In short: steps 1-2 are a one-time setup of the tools, step 3 is what you
repeat every time there is new code to build.
