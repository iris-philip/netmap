import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:multicast_dns/multicast_dns.dart';

class WifiNetwork {
  final String ip;
  final int prefix;
  final String? gateway;
  final String id;
  const WifiNetwork(this.ip, this.prefix, this.gateway, this.id);
  factory WifiNetwork.fromMap(Map<dynamic, dynamic> m) => WifiNetwork(
    m['ip'] as String, m['prefix'] as int, m['gateway'] as String?, m['id'] as String);
  List<String> get hosts {
    // A broad subnet requires an explicit range-selection UI, rather than
    // silently scanning a different /24 or flooding tens of thousands of hosts.
    if (prefix < 22 || prefix > 30) {
      throw StateError('Supported Wi-Fi subnet sizes are /22 through /30. This network is /$prefix.');
    }
    final address = ip.split('.').fold<int>(0, (a, b) => (a << 8) | int.parse(b));
    final mask = (0xffffffff << (32 - prefix)) & 0xffffffff;
    final first = address & mask;
    final last = first | (~mask & 0xffffffff);
    return [for (var n = first + 1; n < last; n++)
      if (n != address) [24, 16, 8, 0].map((s) => (n >> s) & 255).join('.')];
  }
}

class Device {
  final String ip;
  final List<int> ports;
  final bool phone;
  final bool gateway;
  final String? name;
  const Device(this.ip, {this.ports = const [], this.phone = false, this.gateway = false, this.name});
  String get label => phone ? (Platform.isWindows ? 'This PC' : 'This phone') : gateway ? 'Gateway' : 'Network device';
  String get displayName => name ?? label;
  String get services => ports.isEmpty ? 'No open probed ports' : ports.map((p) => '${serviceNames[p] ?? 'TCP'} :$p').join(' · ');
}

const serviceNames = <int, String>{22:'SSH', 80:'HTTP', 443:'HTTPS', 445:'SMB', 554:'RTSP', 631:'IPP', 8008:'HTTP', 8080:'HTTP', 9100:'Printer'};

class NetworkApi {
  static const channel = MethodChannel('netmap/network');
  MDnsClient? _mdnsClient;
  String? _mdnsInterfaceIp;
  int _mdnsSessions = 0;
  bool _multicastLockHeld = false;

  Future<void> startNameLookup(WifiNetwork network) async {
    if (_mdnsSessions > 0) {
      if (_mdnsInterfaceIp != network.ip) {
        throw StateError('mDNS lookup is already active on a different network.');
      }
      _mdnsSessions++;
      return;
    }

    if (Platform.isAndroid) {
      await channel.invokeMethod<void>('acquireMdnsMulticastLock');
      _multicastLockHeld = true;
    }

    final client = MDnsClient();
    try {
      await client.start(interfacesFactory: (type) async {
        final interfaces = await NetworkInterface.list(type: type, includeLoopback: false);
        final selected = interfaces.where((interface) =>
          interface.addresses.any((address) => address.address == network.ip)).toList();
        if (selected.isEmpty) {
          throw StateError('Could not find the active network interface for mDNS lookup.');
        }
        return selected;
      });
      _mdnsClient = client;
      _mdnsInterfaceIp = network.ip;
      _mdnsSessions = 1;
    } catch (error) {
      client.stop();
      if (_multicastLockHeld) {
        _multicastLockHeld = false;
        await channel.invokeMethod<void>('releaseMdnsMulticastLock');
      }
      rethrow;
    }
  }

  Future<void> stopNameLookup() async {
    if (_mdnsSessions == 0) return;
    _mdnsSessions--;
    if (_mdnsSessions > 0) return;
    _mdnsClient?.stop();
    _mdnsClient = null;
    _mdnsInterfaceIp = null;
    if (_multicastLockHeld) {
      _multicastLockHeld = false;
      await channel.invokeMethod<void>('releaseMdnsMulticastLock');
    }
  }

  Future<String?> _lookupName(WifiNetwork network, String ip) async {
    String? reverseName;
    try {
      final address = await InternetAddress(ip).reverse().timeout(const Duration(seconds: 1));
      reverseName = address.host.trim();
    } on SocketException {
    } on TimeoutException {
    }
    if (reverseName != null && reverseName.isNotEmpty && reverseName != ip) return reverseName;

    final client = _mdnsClient;
    if (client == null || _mdnsInterfaceIp != network.ip) return null;
    final reversedAddress = ip.split('.').reversed.join('.');
    final queryName = '$reversedAddress.in-addr.arpa';
    try {
      await for (final record in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(queryName),
        timeout: const Duration(seconds: 1),
      )) {
        final name = record.domainName.trim();
        if (name.isNotEmpty) return name.endsWith('.') ? name.substring(0, name.length - 1) : name;
      }
    } on SocketException {
      return null;
    } on StateError {
      return null;
    }
    return null;
  }

  Future<WifiNetwork> connect() async {
    if (!Platform.isWindows) return WifiNetwork.fromMap(
      (await channel.invokeMethod<Map<dynamic, dynamic>>('network'))!);
    final result = await Process.run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', r'''
$ErrorActionPreference = 'Stop'
$n = Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4DefaultGateway -and $_.IPv4Address } | Select-Object -First 1
if (-not $n) { throw 'Connect this PC to Wi-Fi or Ethernet, then scan again.' }
$a = @($n.IPv4Address)[0]
@{ip=$a.IPAddress; prefix=$a.PrefixLength; gateway=@($n.IPv4DefaultGateway)[0].NextHop; id=[string]$n.InterfaceIndex} | ConvertTo-Json -Compress
''']);
    if (result.exitCode != 0) throw StateError('Could not read the active network. ${result.stderr}');
    return WifiNetwork.fromMap(jsonDecode(result.stdout.toString().trim()) as Map<String, dynamic>);
  }
  Future<String?> saveCsv(String contents) async {
    final name = 'NetMap-${DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first}.csv';
    if (!Platform.isWindows) {
      return channel.invokeMethod<String>('saveCsv', {'name': name, 'contents': contents});
    }
    final encoded = base64Encode(utf8.encode(contents));
    final script = '''
\$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
\$payload = [Console]::In.ReadLine()
\$dialog = New-Object System.Windows.Forms.SaveFileDialog
\$dialog.Title = 'Save network devices as CSV'
\$dialog.Filter = 'CSV files (*.csv)|*.csv'
\$dialog.FileName = '$name'
\$dialog.DefaultExt = 'csv'
\$dialog.AddExtension = \$true
\$dialog.OverwritePrompt = \$true
try {
  if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    \$bytes = [Convert]::FromBase64String(\$payload)
    [IO.File]::WriteAllBytes(\$dialog.FileName, \$bytes)
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    Write-Output \$dialog.FileName
  }
} finally { \$dialog.Dispose() }
''';
    final process = await Process.start('powershell.exe', ['-NoProfile', '-NonInteractive', '-STA', '-Command', script]);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    process.stdin.writeln(encoded);
    await process.stdin.close();
    final exitCode = await process.exitCode;
    await errors;
    final path = (await output).trim();
    if (exitCode != 0) throw PlatformException(code: 'SAVE', message: 'Could not save the CSV file. Choose a writable location and try again.');
    return path.isEmpty ? null : path;
  }
  Future<void> openChrome(String ip) async {
    if (!Platform.isWindows) {
      await channel.invokeMethod<void>('openChrome', {'ip': ip});
      return;
    }
    if (InternetAddress.tryParse(ip)?.type != InternetAddressType.IPv4) {
      throw PlatformException(code: 'ARGS', message: 'Invalid device IP address.');
    }
    final result = await Process.run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', '''
\$ErrorActionPreference = 'Stop'
\$chrome = @(
  "\$env:ProgramFiles\\Google\\Chrome\\Application\\chrome.exe",
  "\${env:ProgramFiles(x86)}\\Google\\Chrome\\Application\\chrome.exe",
  "\$env:LOCALAPPDATA\\Google\\Chrome\\Application\\chrome.exe"
) | Where-Object { Test-Path -LiteralPath \$_ } | Select-Object -First 1
if (-not \$chrome) { throw 'Google Chrome is not installed in a standard location.' }
Start-Process -FilePath \$chrome -ArgumentList 'https://$ip'
''']);
    if (result.exitCode != 0) throw PlatformException(code: 'CHROME', message: 'Could not open Chrome. Check that it is installed.');
  }
  Future<Device?> probe(WifiNetwork network, String ip) async {
    if (Platform.isWindows) {
      if (!network.hosts.contains(ip)) throw StateError('Address is outside the selected subnet.');
      var reachable = false;
      final ports = <int>[];
      for (final port in serviceNames.keys) {
        Socket? socket;
        try {
          socket = await Socket.connect(ip, port, sourceAddress: network.ip,
            timeout: const Duration(milliseconds: 350));
          reachable = true;
          ports.add(port);
        } on SocketException catch (e) {
          if (e.osError?.errorCode == 10061) reachable = true;
        } finally {
          socket?.destroy();
        }
      }
      if (!reachable) return null;
      return Device(ip, ports: ports, gateway: ip == network.gateway, name: await _lookupName(network, ip));
    }
    final response = (await channel.invokeMethod<Map<dynamic, dynamic>>('probe', {'id':network.id, 'ip':ip}))!;
    if (response['reachable'] != true) return null;
    return Device(ip, ports: List<int>.from(response['ports'] as List), gateway: ip == network.gateway,
      name: await _lookupName(network, ip));
  }
}
