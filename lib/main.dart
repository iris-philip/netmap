import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'network.dart';

void main() => runApp(const NetMapApp());

class NetMapApp extends StatelessWidget {
  const NetMapApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NetMap', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff53e0b5), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xff0d1420)),
    home: const NetworkScreen());
}

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});
  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  final api = NetworkApi();
  final devices = <Device>[];
  WifiNetwork? network;
  bool scanning = false;
  bool mapView = true;
  int done = 0, total = 0, generation = 0;
  String? error;
  String status = 'Connect your phone to Wi-Fi, then scan.';

  @override
  void dispose() { generation++; super.dispose(); }

  Future<void> scan() async {
    final run = ++generation;
    setState(() { scanning = true; error = null; done = 0; total = 0; devices.clear(); network = null; status = 'Checking Wi-Fi…'; });
    try {
      final wifi = await api.connect();
      if (!mounted || run != generation) return;
      final hosts = wifi.hosts;
      setState(() { network = wifi; total = hosts.length; devices.add(Device(wifi.ip, phone: true)); status = 'Discovering devices…'; });
      var cursor = 0;
      Future<void> worker() async {
        while (mounted && run == generation && cursor < hosts.length) {
          final ip = hosts[cursor++];
          final device = await api.probe(wifi, ip);
          if (!mounted || run != generation) return;
          setState(() { done++; if (device != null) devices.add(device); });
        }
      }
      await Future.wait(List.generate(math.min(16, hosts.length), (_) => worker()));
      if (mounted && run == generation) setState(() { scanning = false; status = 'Scan complete • ${devices.length} devices including this phone'; });
    } catch (e) {
      if (mounted && run == generation) setState(() {
        generation++;
        scanning = false;
        error = e is PlatformException ? e.message ?? e.code : e.toString();
        status = 'Scan could not finish. Results may be partial.';
      });
    }
  }

  void stop() => setState(() { generation++; scanning = false; status = 'Scan stopped • partial results'; });

  void detail(Device d) => showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (context) => SafeArea(
    child: Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 28), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(d.label, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12), SelectableText(d.ip, style: const TextStyle(fontSize: 20)),
      const SizedBox(height: 12), Text(d.phone ? 'Local Wi-Fi interface' : d.services),
      const SizedBox(height: 16), const Text('Lines indicate membership in the same Wi-Fi subnet. Device type and physical connections are not inferred.'),
    ]))));

  Future<void> export() async {
    final text = ['IP,Role,Open TCP ports', ...devices.map((d) => '${d.ip},${d.label},${d.ports.join(';')}')].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device list copied as CSV')));
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...devices]..sort((a,b) {
      int value(String ip) => ip.split('.').fold(0, (a,b) => (a << 8) | int.parse(b));
      return value(a.ip).compareTo(value(b.ip));
    });
    return Scaffold(
      appBar: AppBar(title: const Text('NetMap', style: TextStyle(fontWeight: FontWeight.w800)), actions: [
        IconButton(onPressed: devices.isEmpty ? null : export, icon: const Icon(Icons.copy_all), tooltip: 'Copy devices as CSV'),
      ]),
      body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your network, at a glance.', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            const Icon(Icons.wifi, color: Color(0xff53e0b5)), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(network == null ? 'Wi-Fi discovery' : '${network!.ip}/${network!.prefix}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(status, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ])), Text('${devices.length}', style: Theme.of(context).textTheme.headlineMedium),
          ]))),
          if (scanning) ...[const SizedBox(height: 8), LinearProgressIndicator(value: total == 0 ? null : done / total), const SizedBox(height: 4), Text('$done / $total addresses checked')],
          if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: FilledButton.icon(onPressed: scanning ? stop : scan, icon: Icon(scanning ? Icons.stop : Icons.radar), label: Text(scanning ? 'Stop scan' : 'Scan network'))), const SizedBox(width: 12),
            IconButton.filledTonal(onPressed: () => setState(() => mapView = !mapView), icon: Icon(mapView ? Icons.list : Icons.hub), tooltip: mapView ? 'Show device list' : 'Show topology'),
          ]),
        ])),
        Expanded(child: devices.isEmpty ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.hub_outlined, size: 72, color: Color(0xff53e0b5)), SizedBox(height: 20), Text('Discover your local devices', style: TextStyle(fontSize: 20)), SizedBox(height: 8), Text('Computers, printers, cameras and other devices that respond to network probes will appear here.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
        ]))) : mapView ? Topology(devices: sorted, onTap: detail) : ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: sorted.length,
          itemBuilder: (context,i) { final d = sorted[i]; return Card(child: ListTile(leading: Icon(d.phone ? Icons.smartphone : d.gateway ? Icons.router : Icons.devices), title: Text(d.label), subtitle: Text('${d.ip}\n${d.phone ? 'Local interface' : d.services}'), isThreeLine: true, trailing: const Icon(Icons.chevron_right), onTap: () => detail(d))); })),
        const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 16), child: Text('Logical subnet map • Some devices may not respond.\nScan only networks you own or have permission to inspect.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.white54))),
      ])),
    );
  }
}

class Topology extends StatelessWidget {
  final List<Device> devices;
  final ValueChanged<Device> onTap;
  const Topology({super.key, required this.devices, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final side = math.max(600.0, devices.length * 48.0);
    final center = Offset(side / 2, side / 2);
    final radius = side * .37;
    final positions = List.generate(devices.length, (i) { final a = 2 * math.pi * i / devices.length - math.pi / 2; return center + Offset(math.cos(a), math.sin(a)) * radius; });
    return InteractiveViewer(minScale: .5, maxScale: 8,
      child: Center(child: FittedBox(child: SizedBox(width: side, height: side, child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: Links(center, positions))),
        Positioned(left: center.dx - 65, top: center.dy - 35, width: 130, height: 70, child: const Card(color: Color(0xff20453e), child: Center(child: Text('Wi-Fi subnet', style: TextStyle(fontWeight: FontWeight.bold))))),
        for (var i = 0; i < devices.length; i++) Positioned(left: positions[i].dx - 70, top: positions[i].dy - 42, width: 140, height: 84, child: Semantics(button: true, label: '${devices[i].label} ${devices[i].ip}', child: Card(child: InkWell(onTap: () => onTap(devices[i]), borderRadius: BorderRadius.circular(12), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(devices[i].phone ? Icons.smartphone : devices[i].gateway ? Icons.router : Icons.devices, color: const Color(0xff53e0b5)),
          Text(devices[i].label, style: const TextStyle(fontSize: 12)), Text(devices[i].ip, style: const TextStyle(fontSize: 11, color: Colors.white60)),
        ]))))),
      ])))));
  }
}

class Links extends CustomPainter {
  final Offset center;
  final List<Offset> points;
  Links(this.center, this.points);
  @override
  void paint(Canvas canvas, Size size) { final paint = Paint()..color = const Color(0xff35534f)..strokeWidth = 1.5; for (final point in points) { canvas.drawLine(center, point, paint); } }
  @override
  bool shouldRepaint(covariant Links oldDelegate) => true;
}
