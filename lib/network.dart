import 'package:flutter/services.dart';

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
  const Device(this.ip, {this.ports = const [], this.phone = false, this.gateway = false});
  String get label => phone ? 'This phone' : gateway ? 'Gateway' : 'Network device';
  String get services => ports.isEmpty ? 'No open probed ports' : ports.map((p) => '${serviceNames[p] ?? 'TCP'} :$p').join(' · ');
}

const serviceNames = <int, String>{22:'SSH', 80:'HTTP', 443:'HTTPS', 445:'SMB', 554:'RTSP', 631:'IPP', 8008:'HTTP', 8080:'HTTP', 9100:'Printer'};

class NetworkApi {
  static const channel = MethodChannel('netmap/network');
  Future<WifiNetwork> connect() async => WifiNetwork.fromMap(
    (await channel.invokeMethod<Map<dynamic, dynamic>>('network'))!);
  Future<Device?> probe(WifiNetwork network, String ip) async {
    final response = (await channel.invokeMethod<Map<dynamic, dynamic>>('probe', {'id':network.id, 'ip':ip}))!;
    if (response['reachable'] != true) return null;
    return Device(ip, ports: List<int>.from(response['ports'] as List), gateway: ip == network.gateway);
  }
}
