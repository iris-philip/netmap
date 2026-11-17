import 'package:flutter_test/flutter_test.dart';
import 'package:netmap/network.dart';

void main() {
  test('uses actual subnet and excludes phone, network and broadcast', () {
    const wifi = WifiNetwork('192.168.7.130', 25, null, '1');
    expect(wifi.hosts.length, 125);
    expect(wifi.hosts.first, '192.168.7.129');
    expect(wifi.hosts.last, '192.168.7.254');
    expect(wifi.hosts, isNot(contains('192.168.7.130')));
    expect(wifi.hosts, isNot(contains('192.168.7.128')));
    expect(wifi.hosts, isNot(contains('192.168.7.255')));
  });
  test('spans octet boundaries for /23 networks', () {
    const wifi = WifiNetwork('10.0.1.20', 23, null, '1');
    expect(wifi.hosts.length, 509);
    expect(wifi.hosts, contains('10.0.0.255'));
    expect(wifi.hosts, contains('10.0.1.0'));
  });
  test('package discovery respects /25 boundaries and excludes this device', () {
    final ranges = const WifiNetwork('192.168.7.130', 25, null, '1').discoveryRanges;
    expect(ranges.keys, ['192.168.7']);
    expect(ranges.values.single, [129, for (var id = 131; id <= 254; id++) id]);
  });
  test('package discovery splits /22 into exact supported octet ranges', () {
    final ranges = const WifiNetwork('10.0.1.20', 22, null, '1').discoveryRanges;
    expect(ranges.keys, ['10.0.0', '10.0.1', '10.0.2', '10.0.3']);
    expect(ranges['10.0.1'], isNot(contains(20)));
    expect(ranges.values.expand((ids) => ids).every((id) => id >= 1 && id <= 254), isTrue);
    expect(ranges.values.fold<int>(0, (total, ids) => total + ids.length), 1015);
  });
  test('package discovery respects small /30 ranges', () {
    expect(const WifiNetwork('192.168.1.5', 30, null, '1').discoveryRanges,
      {'192.168.1': [6]});
  });
  test('refuses unsupported ranges rather than silently truncating', () {
    expect(() => const WifiNetwork('10.0.0.2', 16, null, '1').hosts, throwsStateError);
  });
}
