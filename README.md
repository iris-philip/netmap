# NetMap

A Flutter Android app that discovers responding IPv4 devices on the phone's connected Wi-Fi network and displays a logical topology map. Discovery runs locally; no server or account is required.

## Features

- Reads the actual Wi-Fi IPv4 address, prefix, and gateway from Android.
- Discovers responding hosts on /22 through /30 networks using bounded TCP probes.
- Uses native Android sockets attached to Wi-Fi even when mobile data is enabled.
- Displays a zoomable subnet map, device details, responding ports, progress, stop/rescan, and CSV copying.
- Probes TCP ports 22, 80, 443, 445, 554, 631, 8008, 8080, and 9100. An accepted connection or explicit refusal counts as a response.

## Requirements

- Flutter 3.47.9 stable / Dart 3.13.7 (the versions used for the verified builds).
- Android SDK Platform 36, Build Tools 36.0.0, NDK 28.2.13676358, and CMake 3.22.1.
- Java compatible with the bundled Gradle 9.3.1 / Android Gradle Plugin 9.1.0 build. The verified environment used Android Studio's bundled Java 25.
- Android 7.0 / API 24 or newer. A physical Android phone is needed to validate real Wi-Fi discovery; emulator networking is virtualized.

## Run and check

From the repository root:

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

The Android project is included. Flutter creates machine-local SDK paths when preparing the project; do not commit `android/local.properties`.

Build an APK with both 32-bit and 64-bit ARM support for phones:

```sh
flutter build apk --release --target-platform 'android-arm,android-arm64'
```

For an x86-64 Android emulator:

```sh
flutter build apk --debug --target-platform android-x64
```

Release builds are unsigned so the developer or F-Droid can sign them separately. Flutter copies the output into `build/app/outputs/flutter-apk/`; check the build log for the filename. Sign the resulting APK with your own persistent release key using Android `apksigner`, or let F-Droid sign its source build. No private keys, passwords, or signing backups belong in this repository.

## Verification status

`flutter analyze` and all three subnet tests passed. The x86-64 debug APK built, installed, and launched in an API 37 Android emulator. The ARM 32/64-bit release APK also built successfully. Real-device discovery has not been verified. A separately signed release APK passed signature, alignment, and payload integrity checks; its private signing material is excluded from this source package.

## Limits

This app cannot guarantee finding every device. Firewalls, sleeping devices, client isolation, VLANs, VPNs, and IPv6-only networks can restrict visibility. A firewall can also refuse connections on behalf of a host. Device types, hostnames, MAC addresses, and vendors are not inferred.

Map lines show membership in the same subnet, not physical cable or switch links. Physical topology and fuller inventories require router/AP client tables or managed switch data such as SNMP/LLDP. Gateway labeling only appears if its address responds to the probes.

Stop prevents scheduling more hosts and ignores stale results; active probes finish within their timeouts. Scans run in the foreground and are not persisted across restarts. Scan only networks you own or have permission to inspect.

The included project targets SDK 36. If upgrading to target API 37 or above, declare `android.permission.ACCESS_LOCAL_NETWORK` in the manifest; native runtime permission handling is already included. See [Android local network permissions](https://developer.android.com/privacy-and-security/local-network-permission).

## Publication status

NetMap is licensed under [MIT](LICENSE). The permanent application ID is `io.github.irisphilip.netmap`; earlier test APKs used `com.example.netmap` and are separate Android apps.

Store descriptions, a changelog, privacy information, a Linux Android verification workflow, and a candidate F-Droid recipe are included. F-Droid publication still requires review and a successful F-Droid build. No approval or reproducible-build verification is claimed. See [packaging notes](fdroid/README.md) and the [privacy statement](docs/PRIVACY.md).

See the [F-Droid submission guide](https://f-droid.org/docs/Submitting_to_F-Droid_Quick_Start_Guide/).
