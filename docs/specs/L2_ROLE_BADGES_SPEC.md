# Specification: STP Root Bridge & IGMP Querier Role Badges for ARP Scout

## 1. Overview & Goal
Add **Passive Layer 2 Role Identification (`STP Root Bridge` & `IGMP Querier`)** to **ARP Scout** (`tom-mcguire/arp-scout`).

When scanning a show or AV subnet with ARP Scout, technicians see a flat list of IP addresses, MACs, and OUI vendors (e.g., Cisco, Luminex, Netgear, ETC). Knowing *which* of those switches has won the **Spanning Tree Protocol (STP / RSTP) Root Bridge** election and *which* switch is acting as the **Active IGMP Querier**—without needing switch login credentials or SNMP—immediately reveals the logical center of the network and alerts the technician if an edge switch has accidentally taken over either role.

This feature runs a lightweight, non-intrusive passive listener alongside `SubnetScannerService` to capture standard L2/L3 control frames (`01:80:C2:00:00:00` BPDUs and `224.0.0.1` IGMP General Queries) and stamps matching `ArpHostRecord` rows with high-visibility role badges.

---

## 2. Passive Control-Frame Detection Logic

During or immediately after a subnet scan (`SubnetScannerService`), run a bounded **2.5-second passive capture window** on the selected adapter:

### 2.1 STP / RSTP Root Bridge Identification (`01:80:C2:00:00:00`)
* **Trigger:** Any IEEE 802.1D / 802.1w BPDU frame arriving on the adapter.
* **Header Extraction:**
  * **Root Bridge Identifier (8 bytes):** Bytes `17–24` of the Ethernet payload (2-byte Root Priority + 6-byte **Root Bridge System MAC**).
  * **Designated Bridge Identifier (8 bytes):** Bytes `29–36` (2-byte Priority + 6-byte MAC of the directly connected upstream switch).
* **Host Correlation:**
  * Normalize the 6-byte **Root Bridge System MAC** (`aa:bb:cc:dd:ee:ff`).
  * Match against `ArpHostRecord.macAddress` in the active scan list.
  * Mark the matching host with `isStpRootBridge = true` and store `stpRootPriority` (e.g., `32768`, `4096`).

### 2.2 Active IGMP Querier Identification (`224.0.0.1`)
* **Trigger:** Any incoming IPv4 packet addressed to `224.0.0.1` with IP Protocol `2` (IGMP) and IGMP Type `0x11` (Membership General Query).
* **Header Extraction:**
  * **Querier IPv4 Address:** IPv4 Source Address (`bytes 12–15` of IPv4 header).
  * **IGMP Version:** `IGMPv2` if IGMP payload is `8` bytes; `IGMPv3` if IGMP payload is `>= 12` bytes.
* **Host Correlation:**
  * Match `querierIp` directly against `ArpHostRecord.ipAddress` and set `isIgmpQuerier = true` and `igmpQuerierVersion` (`"IGMPv2"` / `"IGMPv3"`).

---

## 3. Architecture & Model Changes

```
lib/
├── data/
│   └── services/
│       └── scanner/
│           ├── l2_role_sniffer_service.dart      <-- [NEW] 2.5s passive BPDU & IGMP Query listener
│           └── subnet_scanner_service.dart       <-- Invoke L2RoleSnifferService during scan
├── domain/
│   └── models/
│       └── arp_host_record.dart                  <-- Add isStpRootBridge, stpPriority, isIgmpQuerier
└── ui/
    └── features/
        └── scout/
            ├── view_models/
            │   └── arp_scout_view_model.dart     <-- Correlate sniffed MAC/IP roles with host list
            └── views/
                ├── arp_filter_bar.dart           <-- Add "Infrastructure / Roles" quick filter
                ├── arp_table_view.dart           <-- Render [STP ROOT] & [IGMP QUERIER] pills
                └── arp_detail_panel.dart         <-- Show STP Priority & IGMP Query details
```

### 3.1 `ArpHostRecord` Extensions (`lib/domain/models/arp_host_record.dart`)
```dart
final bool isStpRootBridge;
final int? stpRootPriority;
final bool isIgmpQuerier;
final String? igmpQuerierVersion; // e.g. "IGMPv2", "IGMPv3"
```

---

## 4. UI & Diagnostic Specification

1. **`ArpTableView` Role Pills:**
   * **`👑 STP ROOT`** (Amber/Gold pill) when `record.isStpRootBridge == true`.
   * **`📡 IGMP QUERIER`** (Cyan/Teal pill) when `record.isIgmpQuerier == true`.
2. **`ArpDetailPanel` Details:**
   * Show Root Bridge priority and IGMP Querier version.
3. **Misalignment Alert:**
   * Alert if STP Root and IGMP Querier reside on different switches.

---

## 5. Implementation Checklist for Agent
1. Create `L2RoleSnifferService` to capture BPDUs and IGMP General Queries.
2. Extend `ArpHostRecord` with role fields.
3. Correlate sniffed Root MAC and Querier IP in `ArpScoutViewModel`.
4. Render `STP ROOT` and `IGMP QUERIER` badges in `ArpTableView` and `ArpDetailPanel`.
5. Add unit tests for BPDU and IGMP packet parsing. Verify with `flutter analyze` and `flutter test`.
