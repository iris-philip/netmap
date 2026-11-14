# NetMap

NetMap discovers responding IPv4 devices on a connected local network and displays a logical subnet map. The Flutter app runs on Android and Windows; discovery is performed locally without a server or account.

## Features

- Reads the Wi-Fi address, prefix, and gateway from Android, or the active IPv4 configuration on Windows.
- Discovers responding hosts on /22 through /30 networks using bounded TCP probes.
- On Android, attaches sockets to Wi-Fi even when mobile data is enabled.
- Displays a zoomable subnet map, device details, responding ports, scan progress, stop/rescan, and CSV export.
- Looks up reverse-DNS and mDNS names when available; it does not infer device types, MAC addresses, or vendors.
- Probes TCP ports 22, 80, 443, 445, 554, 631, 8008, 8080, and 9100. An accepted connection or explicit refusal counts as a response.

## Android

### Requirements

- Flutter 3.47.9 stable / Dart 3.13.7.
- Android SDK Platform 36, Build Tools 36.0.0, NDK 28.2.13676358, and CMake 3.22.1.
- Java compatible with the bundled Gradle 9.3.1 / Android Gradle Plugin 9.1.0 build.
- Android 7.0 / API 24 or newer. A physical phone is needed to validate real Wi-Fi discovery; emulator networking is virtualized.

### Run and check

From the repository root:

```powershell
.\setup.ps1
.\run.ps1 android
```

Or use Flutter directly:

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Flutter creates machine-local SDK paths while preparing the project; do not commit `android/local.properties`.

Build an unsigned APK with both 32-bit and 64-bit ARM support:

```sh
flutter build apk --release --target-platform 'android-arm,android-arm64'
```

Release builds are unsigned so the developer or F-Droid can sign them separately. No private keys, passwords, or signing backups belong in this repository.

## Windows

The Windows app discovers devices on the active IPv4 interface. Install Flutter with Windows desktop support and the Visual Studio C++ desktop build tools. `environment.ps1` uses `FLUTTER_ROOT` when set, or finds Flutter on `PATH`.

```powershell
.\setup.ps1
.\run.ps1 windows
.\Build-Windows.ps1
```

`Build-Windows.ps1` creates a release build and a ZIP under `dist`. To create the optional installer, install Inno Setup and run:

```powershell
.\Build-Installer.ps1
```

The installer script stages the Visual C++ runtime DLLs locally; they and the generated installer are excluded from Git.

## Verification status

The Android source has previously passed `flutter analyze` and subnet tests, and an earlier revision was built and launched in an API 37 emulator. Real-device discovery has not been verified. Re-run the checks above for the current source revision.

## Limits

NetMap cannot guarantee finding every device. Firewalls, sleeping devices, client isolation, VLANs, VPNs, and IPv6-only networks can restrict visibility. A firewall can also refuse connections on behalf of a host. Names depend on local reverse-DNS or mDNS responses and may be absent or misleading.

Map lines show membership in the same subnet, not physical cable or switch links. Physical topology and fuller inventories require router/AP client tables or managed switch data such as SNMP/LLDP. Gateway labeling only appears if its address responds to the probes.

Stop prevents scheduling more hosts and ignores stale results; active probes finish within their timeouts. Scans run in the foreground and are not persisted across restarts. Scan only networks you own or have permission to inspect.

For Android targets API 37 and above, the app requests `android.permission.ACCESS_LOCAL_NETWORK` at runtime. See [Android local network permissions](https://developer.android.com/privacy-and-security/local-network-permission).

## Publication status

NetMap is licensed under [MIT](LICENSE). The permanent application ID is `io.github.irisphilip.netmap`; earlier test APKs used `com.example.netmap` and are separate Android apps.

Store descriptions, a changelog, privacy information, a Linux Android verification workflow, and a candidate F-Droid recipe are included. F-Droid publication still requires review and a successful F-Droid build. No approval or reproducible-build verification is claimed. See [packaging notes](fdroid/README.md) and the [privacy statement](docs/PRIVACY.md).

See the [F-Droid submission guide](https://f-droid.org/docs/Submitting_to_F-Droid_Quick_Start_Guide/).
