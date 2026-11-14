import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'network.dart';

void main() => runApp(const NetMapApp());

enum AppAccent {
  mint('Default Mint', Color(0xff53e0b5)),
  red('Modern Red', Color(0xffff5a68)),
  blue('Electric Blue', Color(0xff448aff));
  const AppAccent(this.label, this.color);
  final String label;
  final Color color;
}

class NetMapApp extends StatefulWidget {
  const NetMapApp({super.key});
  @override
  State<NetMapApp> createState() => _NetMapAppState();
}

class _NetMapAppState extends State<NetMapApp> {
  AppAccent accent = AppAccent.mint;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NetMap', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: accent.color, brightness: Brightness.dark)
        .copyWith(primary: accent.color, onPrimary: const Color(0xff07131c)),
      scaffoldBackgroundColor: const Color(0xff0d1420)),
    home: NetworkScreen(accent: accent, onAccentChanged: (value) => setState(() => accent = value)));
}

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key, required this.accent, required this.onAccentChanged});
  final AppAccent accent;
  final ValueChanged<AppAccent> onAccentChanged;
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
  String status = 'Connect to your local network, then scan.';

  @override
  void dispose() { generation++; super.dispose(); }

  Future<void> scan() async {
    final run = ++generation;
    var nameLookupStarted = false;
    void addWarning(String message) {
      if (mounted) setState(() => error = error == null ? message : '$error\n$message');
    }
    setState(() { scanning = true; error = null; done = 0; total = 0; devices.clear(); network = null; status = 'Checking Wi-Fi…'; });
    try {
      final wifi = await api.connect();
      if (!mounted || run != generation) return;
      final hosts = wifi.hosts;
      setState(() { network = wifi; total = hosts.length; devices.add(Device(wifi.ip, phone: true)); status = 'Discovering devices…'; });
      try {
        await api.startNameLookup(wifi);
        nameLookupStarted = true;
      } on SocketException catch (e) {
        addWarning('mDNS name lookup is unavailable: ${e.message}');
      } on PlatformException catch (e) {
        addWarning('mDNS name lookup is unavailable: ${e.message ?? e.code}');
      } on StateError catch (e) {
        addWarning('mDNS name lookup is unavailable: $e');
      }
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
      if (mounted && run == generation) setState(() { scanning = false; status = 'Scan complete • ${devices.length} devices including this device'; });
    } catch (e) {
      if (mounted && run == generation) setState(() {
        generation++;
        scanning = false;
        error = e is PlatformException ? e.message ?? e.code : e.toString();
        status = 'Scan could not finish. Results may be partial.';
      });
    } finally {
      if (nameLookupStarted) {
        try {
          await api.stopNameLookup();
        } on PlatformException catch (e) {
          addWarning('Could not release the mDNS multicast lock: ${e.message ?? e.code}');
        }
      }
    }
  }

  void stop() => setState(() { generation++; scanning = false; status = 'Scan stopped • partial results'; });

  Future<void> openDevice(Device d) async {
    try {
      await api.openChrome(d.ip);
    } on PlatformException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Could not open Chrome.')));
    }
  }

  void detail(Device d) => showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (context) => SafeArea(
    child: Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 28), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(d.displayName, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12), SelectableText(d.ip, style: const TextStyle(fontSize: 20)),
      if (d.name != null) ...[
        const SizedBox(height: 8), Text('Device type: ${d.label}'),
      ],
      const SizedBox(height: 12), Text(d.phone ? 'Local network interface' : d.services),
      const SizedBox(height: 16), FilledButton.icon(
        onPressed: () => openDevice(d), icon: const Icon(Icons.open_in_new),
        label: Text('Open https://${d.ip} in Chrome')),
      const SizedBox(height: 16), const Text('Lines indicate membership in the same local subnet. Device type and physical connections are not inferred.'),
    ]))));

  bool savingCsv = false;
  Future<void> export() async {
    if (savingCsv) return;
    setState(() => savingCsv = true);
    String field(String value) => '"${value.replaceAll('"', '""')}"';
    final text = '\uFEFF${[
      ['IP', 'Name', 'Role', 'Open TCP ports'],
      ...devices.map((d) => [d.ip, d.name ?? '', d.label, d.ports.join(';')]),
    ].map((row) => row.map(field).join(',')).join('\r\n')}\r\n';
    try {
      final path = await api.saveCsv(text);
      if (mounted && path != null) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV saved: $path')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the CSV file. Please try another location.')));
    } finally {
      if (mounted) setState(() => savingCsv = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    final sorted = [...devices]..sort((a,b) {
      int value(String ip) => ip.split('.').fold(0, (a,b) => (a << 8) | int.parse(b));
      return value(a.ip).compareTo(value(b.ip));
    });
    return Scaffold(
      appBar: AppBar(title: Row(mainAxisSize: MainAxisSize.min, children: [
        if (defaultTargetPlatform != TargetPlatform.windows) ...[
          ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset(
            'assets/branding/iris-logo.png', width: 48, height: 48,
            fit: BoxFit.contain, filterQuality: FilterQuality.high,
            semanticLabel: 'Iris logo',
          )),
          const SizedBox(width: 12),
        ],
        const Flexible(child: Text('NetMap', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800))),
      ]), actions: [
        PopupMenuButton<AppAccent>(
          tooltip: 'Control color',
          icon: const Icon(Icons.palette_outlined),
          initialValue: widget.accent,
          onSelected: widget.onAccentChanged,
          itemBuilder: (context) => AppAccent.values.map((value) => CheckedPopupMenuItem<AppAccent>(
            value: value, checked: value == widget.accent,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, color: value.color, size: 16),
              const SizedBox(width: 10), Text(value.label),
            ]),
          )).toList(),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: savingCsv ? null : export,
            icon: const Icon(Icons.save_alt, size: 16),
            label: Text(savingCsv ? 'Saving...' : 'Save CSV'),
          ),
        ),
      ]),
      body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your network, at a glance.', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            Icon(Icons.wifi, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(network == null ? 'Network discovery' : '${network!.ip}/${network!.prefix}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(status, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ])), Text('${devices.length}', style: Theme.of(context).textTheme.headlineMedium),
          ]))),
          if (scanning) ...[const SizedBox(height: 8), LinearProgressIndicator(value: total == 0 ? null : done / total), const SizedBox(height: 4), Text('$done / $total addresses checked')],
          if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              visualDensity: VisualDensity.compact,
            ),onPressed: scanning ? stop : scan, icon: Icon(scanning ? Icons.stop : Icons.radar), label: Text(scanning ? 'Stop scan' : 'Scan network'))), const SizedBox(width: 12),
            IconButton.filledTonal(onPressed: () => setState(() => mapView = !mapView), icon: Icon(mapView ? Icons.list : Icons.hub), tooltip: mapView ? 'Show device list' : 'Show topology'),
          ]),
        ])),
        Expanded(child: devices.isEmpty ? Center(child: Padding(padding: EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.hub_outlined, size: 72, color: Theme.of(context).colorScheme.primary), SizedBox(height: 20), Text('Discover your local devices', style: TextStyle(fontSize: 20)), SizedBox(height: 8), Text('Computers, printers, cameras and other devices that respond to network probes will appear here.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
        ]))) : mapView ? Topology(devices: sorted, onTap: detail) : ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: sorted.length,
          itemBuilder: (context,i) { final d = sorted[i]; return Card(child: ListTile(leading: Icon(d.phone ? Icons.smartphone : d.gateway ? Icons.router : Icons.devices), title: Text(d.displayName), subtitle: Text('${d.name == null ? '' : '${d.label} • '}${d.ip}\n${d.phone ? 'Local interface' : d.services}'), isThreeLine: true, trailing: const Icon(Icons.chevron_right), onTap: () => detail(d))); })),
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
        Positioned.fill(child: CustomPaint(painter: Links(center, positions, Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)))),
        Positioned(left: center.dx - 65, top: center.dy - 35, width: 130, height: 70, child: Card(color: Theme.of(context).colorScheme.primaryContainer, child: Center(child: Text('Local subnet', style: TextStyle(fontWeight: FontWeight.bold))))),
        for (var i = 0; i < devices.length; i++) Positioned(left: positions[i].dx - 70, top: positions[i].dy - 42, width: 140, height: 84, child: Semantics(button: true, label: '${devices[i].displayName} ${devices[i].ip}', child: Card(child: InkWell(onTap: () => onTap(devices[i]), borderRadius: BorderRadius.circular(12), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(devices[i].phone ? Icons.smartphone : devices[i].gateway ? Icons.router : Icons.devices, color: Theme.of(context).colorScheme.primary),
          Text(devices[i].displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)), Text(devices[i].ip, style: const TextStyle(fontSize: 11, color: Colors.white60)),
        ]))))),
      ])))));
  }
}

class Links extends CustomPainter {
  final Offset center;
  final List<Offset> points;
  final Color color;
  Links(this.center, this.points, this.color);
  @override
  void paint(Canvas canvas, Size size) { final paint = Paint()..color = color..strokeWidth = 1.5; for (final point in points) { canvas.drawLine(center, point, paint); } }
  @override
  bool shouldRepaint(covariant Links oldDelegate) => true;
}
