# Inter-App Integration Specification: ARP Scout ↔ Net Route Scout

> **Target Audience**: AI Agent / Developer managing **ARP Scout** (`arp_scout`)  
> **Companion Application**: **Net Route Scout** (`net_route_scout`, located at `../route-tracer`)  
> **Goal**: Allow ARP Scout to (1) launch or command Net Route Scout to immediately trace a selected device with the identical network adapter pre-selected, and (2) accept incoming launch commands from Net Route Scout to scan a specific subnet without manual configuration.

---

## 1. Protocol & Contract Overview

The two applications communicate via:
1. **Command Line Arguments** (cold launch when companion is closed).
2. **Local Loopback Socket IPC** (warm handoff when companion is already open).
3. **Custom URI Scheme** (optional deep linking: `arpscout://` and `netroutescout://`).

### Shared Parameter Specification

| Parameter | CLI Flag | JSON IPC Key | URI Query Param | Description | Example |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Target Host** | `--target <ip>` | `"target"` | `target` | Destination IPv4 for Route Scout to trace | `192.168.1.50` |
| **Subnet CIDR** | `--subnet <cidr>` | `"subnet"` | `subnet` | Subnet for ARP Scout to sweep | `192.168.1.0/24` |
| **Network Adapter IP** | `--adapter-ip <ip>` | `"adapterIp"` | `adapterIp` | **Primary matching key** for the local interface | `192.168.1.150` |
| **Network Adapter Name**| `--adapter-name <name>`| `"adapterName"`| `adapterName`| Secondary fallback matching key | `eth0`, `en0`, `Wi-Fi` |
| **Auto-Execute** | `--auto-start` | `"autoStart"` | `autoStart=true`| If true, trigger scan/trace immediately | Flag present / `true` |

---

## 2. Outbound: Launching Net Route Scout from ARP Scout

### 2.1 UI Entrypoint
In [`lib/ui/features/scanner/views/`](lib/ui/features/scanner/views/):
* On the **Discovered Devices Table**, add a right-click Context Menu and row action button on each host:
  * **"Trace Route in Net Route Scout"** (with `Icons.alt_route` or `Icons.route`).
* In the **Device Detail Panel**, add a prominent action button:
  * **"Trace Path to Host"**.

### 2.2 Executable Resolution Order
When launching Net Route Scout (`net_route_scout`), look up the binary in this order:
1. **Development Sibling Path**:
   * Linux: `../route-tracer/build/linux/x64/release/bundle/net_route_scout` (or `debug/bundle/net_route_scout`)
   * Windows: `..\route-tracer\build\windows\x64\runner\Release\net_route_scout.exe`
   * macOS: `../route-tracer/build/macos/Build/Products/Release/Net Route Scout.app`
2. **Production Suite Directory**:
   * Linux: `/usr/local/bin/net-route-scout` or `/opt/NetworkSuite/net-route-scout`
   * Windows: `%LOCALAPPDATA%\NetworkSuite\net-route-scout.exe`
   * macOS: `/Applications/Net Route Scout.app/Contents/MacOS/net_route_scout`
3. **System `$PATH`**: `net-route-scout` / `net_route_scout`.

### 2.3 Dart Implementation Snippet (`inter_app_launcher.dart`)

```dart
import 'dart:convert';
import 'dart:io';
import '../../../domain/models/network_adapter_info.dart';

class InterAppLauncher {
  static const int routeScoutIpcPort = 44101; // Well-known loopback IPC port

  /// Commands Net Route Scout to trace [targetIp] using [currentAdapter].
  static Future<void> launchRouteTrace({
    required String targetIp,
    required NetworkAdapterInfo currentAdapter,
    bool autoStart = true,
  }) async {
    // 1. Check if Net Route Scout is already running via loopback socket
    try {
      final socket = await Socket.connect('127.0.0.1', routeScoutIpcPort, timeout: const Duration(milliseconds: 300));
      final payload = jsonEncode({
        'action': 'trace',
        'target': targetIp,
        'adapterIp': currentAdapter.ipAddress,
        'adapterName': currentAdapter.name,
        'autoStart': autoStart,
      });
      socket.write('$payload\n');
      await socket.flush();
      await socket.close();
      return; // Successfully handed off to running instance!
    } catch (_) {
      // Net Route Scout is not running; perform cold process launch
    }

    // 2. Cold process launch with CLI arguments
    final exePath = await _resolveRouteScoutExecutable();
    if (exePath == null) {
      throw Exception('Net Route Scout executable not found on system.');
    }

    final args = [
      '--target', targetIp,
      '--adapter-ip', currentAdapter.ipAddress,
      '--adapter-name', currentAdapter.name,
      if (autoStart) '--auto-start',
    ];

    await Process.start(exePath, args, mode: ProcessStartMode.detached);
  }

  static Future<String?> _resolveRouteScoutExecutable() async {
    final candidatePaths = <String>[
      if (Platform.isLinux) ...[
        '../route-tracer/build/linux/x64/release/bundle/net_route_scout',
        '../route-tracer/build/linux/x64/debug/bundle/net_route_scout',
        '/usr/local/bin/net-route-scout',
        '/opt/NetworkSuite/net-route-scout',
      ],
      if (Platform.isWindows) ...[
        r'..\route-tracer\build\windows\x64\runner\Release\net_route_scout.exe',
        r'..\route-tracer\build\windows\x64\runner\Debug\net_route_scout.exe',
        '${Platform.environment['LOCALAPPDATA']}\\NetworkSuite\\net-route-scout.exe',
      ],
      if (Platform.isMacOS) ...[
        '../route-tracer/build/macos/Build/Products/Release/Net Route Scout.app/Contents/MacOS/net_route_scout',
        '/Applications/Net Route Scout.app/Contents/MacOS/net_route_scout',
      ],
    ];

    for (final p in candidatePaths) {
      if (await File(p).exists()) return p;
    }
    return null;
  }
}
```

---

## 3. Inbound: Accepting Subnet Scan Commands in ARP Scout

When Net Route Scout launches ARP Scout (e.g. *"Scan This Subnet"*), ARP Scout must:
1. Parse the requested `--subnet` or `--adapter-ip`.
2. Automatically pre-select the exact matching local network adapter.
3. Automatically initiate the ARP sweep if `--auto-start` is true.

### 3.1 Listening for Loopback Socket IPC
ARP Scout should bind a local loopback server on port **`44102`**:
```dart
const int arpScoutIpcPort = 44102;
```

### 3.2 Main Entrypoint Argument Handling (`lib/main.dart`)
Update `main()` in `lib/main.dart`:

```dart
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Parse cold-start CLI args
  String? initialSubnet;
  String? targetAdapterIp;
  String? targetAdapterName;
  bool autoStart = false;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--subnet' && i + 1 < args.length) initialSubnet = args[++i];
    if (args[i] == '--adapter-ip' && i + 1 < args.length) targetAdapterIp = args[++i];
    if (args[i] == '--adapter-name' && i + 1 < args.length) targetAdapterName = args[++i];
    if (args[i] == '--auto-start') autoStart = true;
  }

  // Single instance / IPC listener initialization
  InterAppIpcService.startListener(arpScoutIpcPort, (payload) {
    // Process warm handoff while app is open
    final scannerViewModel = getIt<ScannerViewModel>();
    scannerViewModel.handleIncomingCommand(
      subnet: payload['subnet'] as String?,
      adapterIp: payload['adapterIp'] as String?,
      adapterName: payload['adapterName'] as String?,
      autoStart: payload['autoStart'] == true,
    );
  });

  runApp(MyApp(
    initialSubnet: initialSubnet,
    initialAdapterIp: targetAdapterIp,
    initialAdapterName: targetAdapterName,
    autoStart: autoStart,
  ));
}
```

### 3.3 Adapter Matching Algorithm in `ScannerViewModel`
Ensure the adapter selection prioritizes the IP address:

```dart
void selectMatchingAdapter({String? adapterIp, String? adapterName}) {
  if (availableAdapters.isEmpty) return;

  // 1. Primary match: by IP address (exact physical interface match)
  if (adapterIp != null && adapterIp.isNotEmpty) {
    final match = availableAdapters.firstWhere(
      (a) => a.ipAddress == adapterIp,
      orElse: () => NetworkAdapterInfo.all,
    );
    if (match != NetworkAdapterInfo.all) {
      selectedAdapter = match;
      notifyListeners();
      return;
    }
  }

  // 2. Secondary match: by Interface Name (e.g. "eth0")
  if (adapterName != null && adapterName.isNotEmpty) {
    final match = availableAdapters.firstWhere(
      (a) => a.name.toLowerCase() == adapterName.toLowerCase(),
      orElse: () => NetworkAdapterInfo.all,
    );
    if (match != NetworkAdapterInfo.all) {
      selectedAdapter = match;
      notifyListeners();
      return;
    }
  }
}
```

---

## 4. Verification & Testing Checklist

- [ ] **Warm Handoff**: Open Net Route Scout, then trigger a route trace from ARP Scout. Confirm Net Route Scout receives the target IP without launching a second window.
- [ ] **Cold Handoff**: Close Net Route Scout. Right-click a discovered device in ARP Scout and click "Trace Route in Net Route Scout". Confirm it launches, selects the exact adapter, and starts the trace.
- [ ] **Adapter Parity**: Switch ARP Scout to a secondary NIC (e.g. USB Ethernet `192.168.10.25`). Launch trace. Verify Route Scout automatically selects the `192.168.10.25` adapter.
