import '../../../domain/models/arp_host_record.dart';
import '../../../domain/models/host_status.dart';
import '../oui/oui_lookup_service.dart';

class DemoArpGenerator {
  static List<ArpHostRecord> generateEnterpriseSubnet({
    String subnetCidr = '192.168.10.0/24',
    String interfaceName = 'Ethernet0 (192.168.10.15)',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final prefix = _extractPrefix(subnetCidr);

    final specs = <_DemoSpec>[
      // Core Gateways & Switches
      _DemoSpec(
        hostOctet: 1,
        mac: '00:09:0F:AA:10:01',
        hostname: 'fw-edge-01.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 0.42,
        ttl: 255,
        notes: 'Primary FortiGate Default Gateway (VLAN 10)',
      ),
      // IP Conflict #1: Misconfigured HSRP/VRRP VIP or duplicate static switch management IP
      _DemoSpec(
        hostOctet: 2,
        mac: '00:1C:73:4A:B1:02',
        conflictingMacs: ['00:1C:73:4A:B1:02', '00:1B:54:99:E2:10'],
        hostname: 'sw-core-01.corp.local',
        status: HostStatus.conflict,
        method: 'ARP + ICMP (Conflict)',
        arpType: 'dynamic',
        rtt: 0.85,
        ttl: 64,
        notes:
            'IP CONFLICT: Arista Core Switch (00:1C:73:4A:B1:02) vs Cisco Catalyst (00:1B:54:99:E2:10) claiming .2 management IP',
      ),
      _DemoSpec(
        hostOctet: 3,
        mac: '00:1B:54:81:20:03',
        hostname: 'sw-dist-access-01.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 1.12,
        ttl: 255,
        notes: 'Cisco Catalyst 9300 Stack — MDF Rack A',
      ),
      _DemoSpec(
        hostOctet: 4,
        mac: '24:DE:9A:33:14:04',
        hostname: 'sw-poe-idf2.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 1.48,
        ttl: 255,
        notes: 'HPE Aruba 2930F 48G PoE+ Switch',
      ),
      _DemoSpec(
        hostOctet: 5,
        mac: '4C:5E:0C:77:05:11',
        hostname: 'rtr-branch-oob.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'static',
        rtt: 0.91,
        ttl: 64,
        notes: 'MikroTik CCR2004 OOB Telemetry Router',
      ),

      // Hypervisors & Infrastructure Servers
      _DemoSpec(
        hostOctet: 10,
        mac: '00:50:56:8B:10:10',
        hostname: 'esxi-prod-01.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 0.35,
        ttl: 64,
        notes: 'VMware ESXi 8.0 Hypervisor Host #1 (vmk0)',
      ),
      _DemoSpec(
        hostOctet: 11,
        mac: '00:50:56:8B:10:11',
        hostname: 'esxi-prod-02.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 0.38,
        ttl: 64,
        notes: 'VMware ESXi 8.0 Hypervisor Host #2 (vmk0)',
      ),
      _DemoSpec(
        hostOctet: 12,
        mac: 'BC:24:11:4E:12:01',
        hostname: 'pve-node-01.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 0.44,
        ttl: 64,
        notes: 'Proxmox VE Cluster Node 01 (vmbr0)',
      ),
      // Multi-homed MAC example: Proxmox VIP sharing MAC on .13
      _DemoSpec(
        hostOctet: 13,
        mac: 'BC:24:11:4E:12:01',
        hostname: 'pve-ceph-vip.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 0.46,
        ttl: 64,
        notes: 'Secondary IP bound to Proxmox vmbr0 MAC (Multi-homed)',
      ),
      _DemoSpec(
        hostOctet: 14,
        mac: 'F8:BC:12:90:AA:14',
        hostname: 'idrac-r750-01.corp.local',
        status: HostStatus.arpOnly,
        method: 'ARP Cache',
        arpType: 'dynamic',
        rtt: null,
        ttl: null,
        notes: 'Dell PowerEdge R750 iDRAC9 (ICMP Echo Disabled by Policy)',
      ),
      _DemoSpec(
        hostOctet: 15,
        mac: 'AC:1F:6B:40:15:99',
        hostname: 'ipmi-supermicro-01.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 1.05,
        ttl: 64,
        notes: 'Supermicro BMC IPMI Management Interface',
      ),
      _DemoSpec(
        hostOctet: 20,
        mac: '00:11:32:C8:20:01',
        hostname: 'nas-backup-01.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 0.62,
        ttl: 64,
        notes: 'Synology RackStation RS3621xs+ (10GbE Bond)',
      ),
      _DemoSpec(
        hostOctet: 21,
        mac: '24:5E:BE:19:21:02',
        hostname: 'qnap-san-02.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 0.77,
        ttl: 64,
        notes: 'QNAP TS-h1283XU-RP ZFS Storage',
      ),
      _DemoSpec(
        hostOctet: 25,
        mac: '00:15:5D:0A:25:01',
        hostname: 'dc01-ad.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 0.51,
        ttl: 128,
        notes: 'Active Directory / DNS / DHCP Server (Hyper-V VM)',
      ),

      // Wireless Access Points (Ubiquiti / Meraki)
      _DemoSpec(
        hostOctet: 30,
        mac: '74:83:C2:AA:30:01',
        hostname: 'u6-pro-lobby.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 1.85,
        ttl: 64,
        notes: 'Ubiquiti UniFi U6-Pro Access Point — Main Lobby',
      ),
      _DemoSpec(
        hostOctet: 31,
        mac: '74:83:C2:AA:30:02',
        hostname: 'u6-pro-eng.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 2.10,
        ttl: 64,
        notes: 'Ubiquiti UniFi U6-Pro Access Point — Engineering Floor',
      ),
      _DemoSpec(
        hostOctet: 32,
        mac: '88:15:44:CC:32:10',
        hostname: 'mr46-warehouse.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 2.64,
        ttl: 64,
        notes: 'Cisco Meraki MR46 Wi-Fi 6 AP — Warehouse Bay',
      ),

      // Printers & Facilities
      _DemoSpec(
        hostOctet: 40,
        mac: '30:E1:71:55:40:01',
        hostname: 'hp-mfp-2ndfloor.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 3.40,
        ttl: 64,
        notes: 'HP LaserJet Enterprise MFP M635',
      ),
      _DemoSpec(
        hostOctet: 41,
        mac: '00:80:77:91:41:08',
        hostname: 'brother-label-shipping.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 4.15,
        ttl: 64,
        notes: 'Brother HL-L6200DW Shipping Printer',
      ),

      // IP Conflict #2: Rogue Static IP Camera colliding with a DHCP Workstation!
      _DemoSpec(
        hostOctet: 50,
        mac: '28:57:BE:91:50:CC',
        conflictingMacs: ['28:57:BE:91:50:CC', '3C:97:0E:12:50:AA'],
        hostname: 'cam-loading-dock-04',
        status: HostStatus.conflict,
        method: 'ARP + ICMP (Conflict)',
        arpType: 'dynamic',
        rtt: 14.80,
        ttl: 64,
        notes:
            'IP CONFLICT: Hardcoded Hikvision Camera (28:57:BE:91:50:CC) colliding with Intel Corporate Laptop (3C:97:0E:12:50:AA) in DHCP scope!',
      ),
      _DemoSpec(
        hostOctet: 51,
        mac: 'AC:CC:8E:44:51:01',
        hostname: 'axis-p3245-entrance.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 1.92,
        ttl: 64,
        notes: 'Axis P3245-V Dome Network Camera (PoE)',
      ),
      _DemoSpec(
        hostOctet: 52,
        mac: 'AC:CC:8E:44:51:02',
        hostname: 'axis-p3245-parking.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 2.08,
        ttl: 64,
        notes: 'Axis P3245-V Dome Network Camera (PoE)',
      ),

      // Engineering Workstations, Embedded SBCs & Endpoints
      _DemoSpec(
        hostOctet: 101,
        mac: 'A4:83:E7:21:65:01',
        hostname: 'mbp-tom-dev.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 3.12,
        ttl: 64,
        notes: 'Apple MacBook Pro M3 Max — Engineering',
      ),
      _DemoSpec(
        hostOctet: 102,
        mac: '68:05:CA:3B:66:02',
        hostname: 'ws-netops-01.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 0.78,
        ttl: 128,
        notes: 'Windows 11 NetOps Workstation (Windows Firewall ICMP Enabled)',
      ),
      _DemoSpec(
        hostOctet: 103,
        mac: '50:7B:9D:88:67:03',
        hostname: 'thinkpad-secops-02.corp.local',
        status: HostStatus.arpOnly,
        method: 'ARP Cache',
        arpType: 'dynamic',
        rtt: null,
        ttl: null,
        notes: 'Lenovo ThinkPad T14s — Windows Defender Firewall Blocking ICMP',
      ),
      _DemoSpec(
        hostOctet: 110,
        mac: 'DC:26:32:7F:6E:10',
        hostname: 'rpi4-netprobe-idf1.corp.local',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 1.35,
        ttl: 64,
        notes: 'Raspberry Pi 4B Network Telemetry Probe (IDF-1)',
      ),
      _DemoSpec(
        hostOctet: 111,
        mac: '30:AE:A4:19:6F:11',
        hostname: 'esp32-hvac-sensor-01',
        status: HostStatus.online,
        method: 'ARP + ICMP',
        arpType: 'dynamic',
        rtt: 8.90,
        ttl: 255,
        notes: 'Espressif ESP32 Server Room Temp/Humidity Monitor',
      ),
      _DemoSpec(
        hostOctet: 120,
        mac: 'DA:A1:19:44:78:20',
        hostname: 'iphone-guest-priv',
        status: HostStatus.arpOnly,
        method: 'ARP Cache',
        arpType: 'dynamic',
        rtt: null,
        ttl: null,
        notes: 'Mobile Endpoint using Randomized / Private Wi-Fi MAC (LAA)',
      ),
      _DemoSpec(
        hostOctet: 145,
        mac: '00:0C:29:F1:91:45',
        hostname: 'vm-legacy-build.corp.local',
        status: HostStatus.stale,
        method: 'ARP Cache (Expired)',
        arpType: 'dynamic',
        rtt: null,
        ttl: null,
        notes: 'VM powered down or migrated to another VLAN 12m ago',
      ),
    ];

    return specs.map((s) {
      final ip = '$prefix.${s.hostOctet}';
      final mac = ArpHostRecord.normalizeMac(s.mac);
      final vendor = OuiLookupService.lookupVendor(mac);
      final conflicts = s.conflictingMacs.isNotEmpty
          ? s.conflictingMacs.map(ArpHostRecord.normalizeMac).toList()
          : <String>[mac];

      return ArpHostRecord(
        ipAddress: ip,
        ipNumeric: ArpHostRecord.ipv4ToInt(ip),
        macAddress: mac,
        vendor: vendor,
        hostname: s.hostname,
        subnet: subnetCidr,
        interfaceName: interfaceName,
        status: s.status,
        discoveryMethod: s.method,
        arpType: s.arpType,
        rttMs: s.rtt,
        ttl: s.ttl,
        firstSeenMs: now - 300000,
        lastSeenMs: s.status == HostStatus.stale ? now - 720000 : now,
        responseCount: s.status == HostStatus.conflict ? 14 : 5,
        conflictingMacs: conflicts,
        notes: s.notes,
        rawArpLine:
            '  ${ip.padRight(20)} ${mac.replaceAll(':', '-').toLowerCase().padRight(20)} ${s.arpType}',
      );
    }).toList();
  }

  static String _extractPrefix(String cidr) {
    final ip = cidr.split('/').first.split('-').first.trim();
    final parts = ip.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.${parts[1]}.${parts[2]}';
    }
    return '192.168.10';
  }
}

class _DemoSpec {
  const _DemoSpec({
    required this.hostOctet,
    required this.mac,
    this.conflictingMacs = const [],
    this.hostname,
    required this.status,
    required this.method,
    required this.arpType,
    this.rtt,
    this.ttl,
    required this.notes,
  });

  final int hostOctet;
  final String mac;
  final List<String> conflictingMacs;
  final String? hostname;
  final HostStatus status;
  final String method;
  final String arpType;
  final double? rtt;
  final int? ttl;
  final String notes;
}
