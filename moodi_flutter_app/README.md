# MOODI Controller (Android / Flutter)

A small Android BLE remote for the MOODI ESP32 digital companion. This first version scans for the MOODI BLE service, connects, and sends the six emotion commands that your current ESP32 firmware already understands.

## What this version does

- Scans for the advertised MOODI service UUID.
- Connects to the matching ESP32 peripheral.
- Discovers the existing emotion characteristic.
- Sends `happy`, `sad`, `angry`, `sleepy`, `surprised`, or `neutral` as UTF-8 text.
- Shows connection, scan, and write status in the app.
- Requests the appropriate Android Bluetooth permissions. On Android 11 and older, Android requires foreground location permission for BLE scanning; this app does not read or store location.

## ESP32 compatibility

The app is configured to match the firmware UUIDs used in the MOODI prototype:

```text
Device name: MOODI
Service UUID:        12345678-1234-1234-1234-1234567890AB
Emotion UUID:        12345678-1234-1234-1234-1234567890AC
```

The ESP32 must advertise the service UUID as well as its device name. The current firmware setup should contain the equivalent of:

```cpp
advertising->setName("MOODI");
advertising->addServiceUUID(SERVICE_UUID);
advertising->start();
```

The emotion characteristic must support BLE Write (write with response), as in the current ESP32 sketch. The app sends the exact lowercase text without a newline.

> Keep the ESP32 powered on and advertising. Disconnect the phone from nRF Connect before connecting with this app if nRF Connect is still holding the BLE connection.

## Dependencies

- Flutter SDK (stable; Flutter 3.38.1 or newer recommended)
- Android SDK / Android Studio for local Android builds
- `flutter_reactive_ble` 5.6.0 (BSD-3-Clause)
- `permission_handler` 12.0.3
- `device_info_plus` 12.4.0

## Generate Android platform files locally

This source bundle keeps the generated Android/Gradle wrapper files out of the archive. On the first run, open a terminal in this project folder and execute:

```bash
flutter create --platforms=android --org com.moodi --project-name moodi_app --no-pub .
python3 scripts/prepare_android.py
flutter pub get
flutter doctor -v
flutter run
```

Connect your Android phone with USB debugging enabled, or install the built APK on the phone. On the first scan, allow the Bluetooth permissions requested by Android.

## Build an APK on your own computer

After generating the Android platform files and resolving packages:

```bash
flutter analyze
flutter test
flutter build apk --release
```

The APK will be created at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Build and download the APK using GitHub Actions

The included workflow at `.github/workflows/build-android.yml` creates the Android scaffold, configures BLE permissions, runs analysis and unit tests, and builds the release APK whenever you push to `main` or `master`.

1. Create a new empty GitHub repository, for example `moodi-controller`.
2. Extract this ZIP file on your computer.
3. Open a terminal in the extracted `moodi_flutter_app` folder.
4. Run:

   ```bash
   git init
   git add .
   git commit -m "Add MOODI Flutter controller"
   git branch -M main
   git remote add origin https://github.com/YOUR-USERNAME/moodi-controller.git
   git push -u origin main
   ```

5. Open the repository on GitHub and select **Actions**. Open the latest **Build MOODI Android APK** run.
6. When it succeeds, download the `moodi-android-apk` artifact near the bottom of that workflow run. The APK is inside the downloaded artifact ZIP.

To create a permanent GitHub Release asset, push a version tag after the build workflow is present:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow will attach `app-release.apk` to the generated GitHub Release for that tag.

## Current boundaries / next firmware changes

This app deliberately controls only the features already implemented by the current ESP32 firmware. Brightness control, date/time sync, battery percentage, and device status notifications are not included yet; those require additional BLE characteristics and matching ESP32 firmware changes.

## Test checklist with the real MOODI device

The automated unit tests validate the six command strings and their UTF-8 payloads. After installing the APK, verify these hardware cases:

1. MOODI powered off: scan should time out and show a helpful message.
2. MOODI powered on: scan should find the advertised service and connect.
3. Tap each of the six emotion buttons: the OLED should show the matching expression.
4. Disconnect from the app: the app should return to the disconnected state.
5. Turn MOODI off while connected: the app should report a disconnection.
6. Turn MOODI back on: tap Connect and verify it reconnects.
7. Deny Bluetooth permission: the app should explain that permission is required; grant it in Android settings and retry.

I cannot run the real-hardware checklist without access to your Android phone and MOODI ESP32 board. GitHub Actions provides the reproducible Android build and runs the source analysis and unit tests.
