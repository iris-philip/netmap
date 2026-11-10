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
  test('refuses unsupported ranges rather than silently truncating', () {
    expect(() => const WifiNetwork('10.0.0.2', 16, null, '1').hosts, throwsStateError);
  });
}
