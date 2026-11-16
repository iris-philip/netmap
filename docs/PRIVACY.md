# Privacy

NetMap performs device discovery locally on the Wi-Fi network selected by Android or iOS. It sends TCP connection probes to addresses in the connected IPv4 subnet when you request a scan. Those devices and network infrastructure can observe the probes and the phone's network address.

The app does not require an account, upload scan results to a cloud service, contain advertising or analytics SDKs, or persist scan results across app restarts. No developer-operated server receives scan data.

Saving a CSV exports device IP addresses and responding ports through Android's document picker or iOS Files. The exported file is under the user's control.

The Android app uses Internet/network-state permissions to inspect the Wi-Fi connection and create local network sockets. The iOS app requests local-network access when the user scans. Neither platform needs location access for its current implementation.

This statement describes the NetMap source in this repository. Android, the device vendor, and your network infrastructure have their own privacy behavior.
