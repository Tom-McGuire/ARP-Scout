# Specification: STP Root Bridge & IGMP Querier Role Badges for ARP Scout

## 1. Overview & Goal
Add **Passive Layer 2 Role Identification (`STP Root Bridge` & `IGMP Querier`)** to **ARP Scout** (`tom-mcguire/arp-scout`).

When scanning a show, AV, or broadcast production subnet with ARP Scout, technicians see a flat list of IP addresses, MACs, and OUI vendors (e.g., Cisco, Luminex, Netgear, ETC). Knowing *which* of those switches has won the **Spanning Tree Protocol (STP / RSTP) Root Bridge** election and *which* switch is acting as the **Active IGMP Querier**—without needing switch login credentials or SNMP—immediately reveals the logical center of the network and alerts the technician if an edge switch has accidentally taken over either role.

### Why a Two-Scan Strategy is Required:
* **STP BPDUs (Fast, 2s interval):** IEEE 802.1D / 802.1w bridges transmit BPDUs every **2.0 seconds** by default (Hello Time = 2s). A short, bounded **4-second** capture window guarantees observing at least one (typically two) BPDUs without delaying the user.
* **IGMP General Queries (Slow, 125s interval):** Per RFC 2236 and RFC 3376, the elected active IGMP Querier transmits General Queries (`224.0.0.1`, Type `0x11`) every **125 seconds** by default (Query Interval = 125s, Query Response Interval = 10s). A short 2.5s or 4s capture window will almost always miss the query. Therefore, IGMP query detection must run as a **longer, separate asynchronous background capture (~130 seconds)** or seamlessly integrate with **Continuous-Watch Mode**, progressively badging the querier as soon as a query frame is observed.

---

## 2. Dual-Scan Passive Detection Logic

Instead of a single short window, ARP Scout employs a **2-Phase Decoupled Capture Architecture**:

```
[Start Subnet Scan]
        │
        ├───> Phase 1: Bounded 4s STP Capture (Fast) ───> Badge [👑 STP ROOT] immediately
        │
        └───> Phase 2: Asynchronous ~130s IGMP Listener ─> Badge [📡 IGMP QUERIER] dynamically
              (Persists between sweeps in Continuous-Watch Mode)
```

### 2.1 Phase 1: STP / RSTP Root Bridge Identification (4s Bounded Capture)
* **Target Frame:** IEEE 802.1D / 802.1w Configuration or RST BPDU sent to multicast MAC `01:80:C2:00:00:00`.
* **Execution Window:** Bounded **4.0-second** capture running alongside the active ARP sweep. Exits immediately upon receiving the first valid BPDU or after 4 seconds.
* **Header Extraction:**
  * **Root Bridge Identifier (8 bytes):** Bytes `17–24` of BPDU payload:
    * 2-byte Root Priority (e.g., `32768`, `4096`, `0`)
    * 6-byte **Root Bridge System MAC**
  * **Designated Bridge Identifier (8 bytes):** Bytes `29–36` (2-byte Priority + 6-byte MAC of the upstream bridge on this port).
* **Host Correlation:**
  * Normalize the 6-byte **Root Bridge System MAC** (`AA:BB:CC:DD:EE:FF`).
  * Match against `ArpHostRecord.macAddress` in the active scan list.
  * Mark the matching host with `isStpRootBridge = true` and store `stpRootPriority`.

### 2.2 Phase 2: Active IGMP Querier Identification (~130s Background Capture)
* **Target Frame:** IPv4 packet addressed to All-Hosts multicast `224.0.0.1` with IP Protocol `2` (IGMP) and IGMP Type `0x11` (Membership General Query).
* **Execution Window:**
  * **Single-Sweep Mode:** Spawns as a non-blocking background task running for up to **130 seconds**. The UI remains fully responsive, and hosts are badged dynamically in real-time as soon as the query is detected.
  * **Continuous-Watch Mode:** The background listener remains permanently active across sweep intervals. If an IGMP General Query is observed at any time, it updates or confirms the active querier without resetting.
* **Header Extraction:**
  * **Querier IPv4 Address:** IPv4 Source Address (`bytes 12–15` of IPv4 header).
  * **IGMP Version:**
    * `IGMPv2` if IGMP payload length is `8` bytes.
    * `IGMPv3` if IGMP payload length is `>= 12` bytes (contains Max Response Code, S-flag, QRV, and QQIC fields).
* **Host Correlation:**
  * Match `querierIp` directly against `ArpHostRecord.ipAddress`.
  * Set `isIgmpQuerier = true` and `igmpQuerierVersion` (`"IGMPv2"` / `"IGMPv3"`).
  * If the querier IP was not yet in the ARP table (e.g. silent querier on another subnet/VLAN), emit an info notification or append as an infrastructure node.

---

## 3. Dual Capture Engine Support (`tcpdump` & `tshark`)

To maximize compatibility across development, macOS, Linux, and specialized AV distributions, the capture engine (`L2RoleSnifferService`) implements a dual-backend fallback strategy:
1. **Primary: `tcpdump`** (Standard, zero-overhead, present on nearly all POSIX systems).
2. **Fallback: `tshark`** (Wireshark CLI, useful when installed or if specific BPF privileges require Wireshark group permissions).

### 3.1 STP BPDU Capture Commands
* **`tcpdump` Command:**
  ```bash
  tcpdump -c 1 -i <iface> -nn -e -s 1500 'ether dst 01:80:c2:00:00:00 or ether[14:4] == 0x42420300'
  ```
  *(Terminates immediately after 1 packet with a 4s process timeout).*
* **`tshark` Fallback:**
  ```bash
  tshark -i <iface> -a duration:4 -c 1 -Y "stp" -T fields -e eth.src -e stp.root.hw -e stp.root.prio
  ```

### 3.2 IGMP General Query Capture Commands
* **`tcpdump` Command:**
  ```bash
  tcpdump -c 1 -i <iface> -nn -v -s 1500 'igmp and dst 224.0.0.1 and ip[20] == 0x11'
  ```
  *(Runs asynchronously with a 130s process timeout; exits immediately upon seeing the first query).*
* **`tshark` Fallback:**
  ```bash
  tshark -i <iface> -a duration:130 -c 1 -Y "igmp.type == 0x11 and ip.dst == 224.0.0.1" -T fields -e ip.src -e igmp.version
  ```

---

## 4. Architecture & Model Changes

```
lib/
├── data/
│   └── services/
│       └── scanner/
│           ├── l2_role_sniffer_service.dart      <-- [NEW] Dual-phase (4s STP, 130s IGMP) sniffer with tcpdump/tshark
│           └── subnet_scanner_service.dart       <-- Invokes STP during sweep, triggers IGMP background listener
├── domain/
│   └── models/
│       ├── l2_role_discovery_result.dart         <-- [NEW] Models for StpDiscoveryResult & IgmpQuerierResult
│       └── arp_host_record.dart                  <-- Add isStpRootBridge, stpPriority, isIgmpQuerier, igmpVersion
└── ui/
    └── features/
        └── scout/
            ├── view_models/
            │   └── arp_scout_view_model.dart     <-- Handles background stream, dynamic live badging, continuous-watch
            └── views/
                ├── arp_filter_bar.dart           <-- Add "Infrastructure / Roles" quick filter
                ├── arp_table_view.dart           <-- Render [STP ROOT] & [IGMP QUERIER] pills
                └── arp_detail_panel.dart         <-- Show STP Priority & IGMP Query telemetry
```

### 4.1 Service Interface (`l2_role_sniffer_service.dart`)
```dart
class L2RoleSnifferService {
  /// Fast 4-second bounded capture for STP Root Bridge BPDU
  static Future<StpDiscoveryResult?> captureStpRoot({
    required String interfaceName,
    Duration timeout = const Duration(seconds: 4),
  });

  /// Asynchronous stream for IGMP Membership General Queries (130s or continuous)
  static Stream<IgmpQuerierResult> listenForIgmpQuerier({
    required String interfaceName,
    Duration timeout = const Duration(seconds: 130),
    bool continuous = false,
  });
}
```

### 4.2 `ArpHostRecord` Extensions (`lib/domain/models/arp_host_record.dart`)
```dart
final bool isStpRootBridge;
final int? stpRootPriority;
final bool isIgmpQuerier;
final String? igmpQuerierVersion; // "IGMPv2", "IGMPv3"
```

---

## 5. UI & Diagnostic Specification

1. **`ArpTableView` Role Pills:**
   * **`👑 STP ROOT`** (Amber/Gold pill `#F59E0B`) when `record.isStpRootBridge == true`.
   * **`📡 IGMP QUERIER`** (Cyan/Teal pill `#06B6D4`) when `record.isIgmpQuerier == true`.
   * Live animation/pulse when stamped dynamically by the background IGMP listener.

2. **Continuous-Watch Integration:**
   * When continuous-watch mode is active, the IGMP listener runs continuously in the background between sweep intervals.
   * A subtle status indicator in the status ribbon displays `IGMP Listener: Active (listening for General Queries)`.

3. **`ArpDetailPanel` Infrastructure Details:**
   * Shows Root Bridge priority (`Priority: 4096 (Root)` vs default `32768`).
   * Shows IGMP Querier version (`IGMPv2` / `IGMPv3`) and last query timestamp.

4. **Misalignment Alert:**
   * If both roles are discovered on different switches (different MAC / IP), surface an advisory banner:
     > ⚠️ **STP Root & IGMP Querier Misaligned:** STP Root is at `10.201.100.1` while IGMP Querier is at `10.201.100.254`. In multicast-heavy networks (sACN / Dante), this can cause multicast traffic to cross suboptimal uplinks.

---

## 6. Implementation Checklist
1. Create `L2RoleSnifferService` implementing 4s STP capture and 130s IGMP query listener using `tcpdump` with `tshark` fallback.
2. Extend `ArpHostRecord` with `isStpRootBridge`, `stpRootPriority`, `isIgmpQuerier`, and `igmpQuerierVersion`.
3. Update `ArpScoutViewModel` to run the 4s STP capture during scan and stream IGMP query results dynamically in the background.
4. Integrate with Continuous-Watch mode so the IGMP listener persists across sweeps.
5. Render `STP ROOT` and `IGMP QUERIER` badges in `ArpTableView` and `ArpDetailPanel`.
6. Add unit tests for BPDU and IGMP packet parsing across both `tcpdump` and `tshark` output formats.
7. Verify with `flutter analyze` and `flutter test`.
