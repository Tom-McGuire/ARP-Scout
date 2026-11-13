import 'dart:typed_data';

import 'package:arp_scout/data/services/scanner/l2_role_sniffer_service.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bpdu({
  int priority = 4096,
  List<int> mac = const [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF],
}) {
  return Uint8List.fromList([
    0x01, 0x80, 0xC2, 0, 0, 0, // dst
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55, // src
    0x00, 0x26, // length
    0x42, 0x42, 0x03, // LLC
    0x00, 0x00, 0x02, 0x02, 0x3C, // proto, version, type RST, flags
    priority >> 8, priority & 0xFF, ...mac, // root id
    0, 0, 0, 4, // path cost
    0x80, 0x00, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, // bridge id
    0x80, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ]);
}

Uint8List igmpQuery({
  required int igmpLen,
  String dst = '224.0.0.1',
  int type = 0x11,
}) {
  final total = 20 + igmpLen;
  final dstParts = dst.split('.').map(int.parse).toList();
  return Uint8List.fromList([
    0x01,
    0x00,
    0x5E,
    0,
    0,
    0x01,
    0x00,
    0x11,
    0x22,
    0x33,
    0x44,
    0x55,
    0x08,
    0x00,
    0x45,
    0,
    total >> 8,
    total & 0xFF,
    0,
    0,
    0,
    0,
    1,
    2,
    0,
    0,
    192,
    168,
    1,
    5,
    ...dstParts,
    type,
    100,
    0,
    0,
    ...List.filled(igmpLen - 4, 0),
  ]);
}

void main() {
  test('extracts BPDU root bridge MAC and priority', () {
    final r = L2RoleSnifferService.parseBpdu(bpdu());
    expect(r?.mac, 'AA:BB:CC:DD:EE:FF');
    expect(r?.priority, 4096);
  });

  test('rejects non-BPDU frames', () {
    expect(L2RoleSnifferService.parseBpdu(igmpQuery(igmpLen: 8)), isNull);
    expect(L2RoleSnifferService.parseBpdu(Uint8List(10)), isNull);
  });

  test('parses IGMPv2 and IGMPv3 general queries', () {
    final v2 = L2RoleSnifferService.parseIgmpGeneralQuery(
      igmpQuery(igmpLen: 8),
    );
    expect(v2?.ip, '192.168.1.5');
    expect(v2?.version, 'IGMPv2');
    final v3 = L2RoleSnifferService.parseIgmpGeneralQuery(
      igmpQuery(igmpLen: 12),
    );
    expect(v3?.version, 'IGMPv3');
  });

  test('ignores non-general queries and reports', () {
    expect(
      L2RoleSnifferService.parseIgmpGeneralQuery(
        igmpQuery(igmpLen: 8, dst: '224.1.1.1'),
      ),
      isNull,
    );
    expect(
      L2RoleSnifferService.parseIgmpGeneralQuery(
        igmpQuery(igmpLen: 8, type: 0x16),
      ),
      isNull,
    );
  });

  test('parses tcpdump -xx output into frames', () {
    const out = '''
12:00:00.000 STP 802.1w
\t0x0000:  0180 c200 0000 0011 2233 4455 0026 4242
\t0x0010:  0300 0002 023c 1000 aabb ccdd eeff
12:00:01.000 IP 192.168.1.5 > 224.0.0.1: igmp query
\t0x0000:  0100 5e00 0001
''';
    final frames = L2RoleSnifferService.parseTcpdumpHex(out);
    expect(frames.length, 2);
    expect(frames[0].length, 30);
    final res = L2RoleSnifferService.parseFrames(frames);
    expect(res.stpRootMac, 'AA:BB:CC:DD:EE:FF');
    expect(res.stpRootPriority, 4096);
  });

  test('parses tshark -x output into frames', () {
    const out = '''
Capturing on 'eth0'
0000  01 80 c2 00 00 00 00 11 22 33 44 55 00 26 42 42   .........3DU.&BB
0010  03 00 00 02 02 3c 10 00 aa bb cc dd ee ff         .....<........

0000  01 00 5e 00 00 01                                 ..^...
''';
    final frames = L2RoleSnifferService.parseTsharkHex(out);
    expect(frames.length, 2);
    expect(frames[0].length, 30);
    expect(frames[1].length, 6);
    expect(
      L2RoleSnifferService.parseFrames(frames).stpRootMac,
      'AA:BB:CC:DD:EE:FF',
    );
  });
}
