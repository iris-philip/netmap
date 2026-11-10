# Privacy

NetMap performs device discovery locally on the Wi-Fi network selected by Android. It sends TCP connection probes to addresses in the connected IPv4 subnet when you request a scan. Those devices and network infrastructure can observe the probes and the phone's network address.

The app does not require an account, upload scan results to a cloud service, contain advertising or analytics SDKs, or persist scan results across app restarts. No developer-operated server receives scan data.

Choosing the copy action puts device IP addresses and responding ports on Android's system clipboard. Clipboard access and retention are controlled by Android and other applications that the user authorizes.

The app uses Internet/network-state permissions to inspect the Wi-Fi connection and create local network sockets. It does not need location access for its current implementation. If targeting API 37 or newer in a future release, local-network permission will also be needed.

This statement describes the NetMap source in this repository. Android, the device vendor, and your network infrastructure have their own privacy behavior.
