# Specification: Quick Web UI & Service Port Probe for ARP Scout

## 1. Overview & Goal
Add a **Fast TCP Web & Management Port Probe** with **One-Click Browser Launch Buttons** to **ARP Scout** (`tom-mcguire/arp-scout`).

In AV, entertainment lighting, and broadcast environments, almost every managed switch, sACN/Art-Net node, media server, and DSP exposes a web configuration interface—often on standard HTTP/HTTPS ports (`80`, `443`) or alternate web management ports (`8080` through `8085`, commonly used by ETC gateways, Luminex nodes, media server web remotes, and Q-SYS/Dante web panels).

After ARP Scout discovers active hosts on a subnet, this feature performs a rapid, concurrent, non-blocking TCP socket probe across ports `80`, `443`, and `8080–8085`, displays clickable port pills directly in the UI, and provides a one-click **"Open in Web Browser"** button formatted with the exact protocol, IP address, and port (`http://<ip>:<port>` or `https://<ip>`).

---

## 2. Target Ports & Probe Behavior

### 2.1 Scanned Port List
| Port | Scheme | Typical AV / Network Service |
| :--- | :--- | :--- |
| **`80`** | `http://` | Standard Switch / Node Web UI |
| **`443`** | `https://` | Secure Switch / Enterprise Web UI |
| **`8080`** | `http://` | Alternate Web UI / Media Server Control |
| **`8081`** | `http://` | Secondary Device / Node Web Service |
| **`8082`** | `http://` | Companion / Web Control Interface |
| **`8083`** | `http://` | Auxiliary Device Web Management |
| **`8084`** | `http://` | Auxiliary Device Web Management |
| **`8085`** | `http://` | Auxiliary Device Web Management |

### 2.2 Fast Non-Blocking Socket Execution
* **Concurrency & Timeout:**
  * Run probes only against hosts confirmed `online` (`HostStatus.online`) by the ARP/ICMP sweep.
  * Use Dart's native `Socket.connect(ip, port, timeout: Duration(milliseconds: 300))`—immediately destroying the socket (`socket.destroy()`) upon successful TCP SYN-ACK handshake.
  * Batch probes with a concurrency semaphore (e.g., max 32 concurrent sockets) so scanning 50 active hosts across all 8 ports (`400` lightweight SYN checks) completes in **< 1.5 seconds** without exhausting OS ephemeral file descriptors.
* **Toggleable Option:**
  * Include a compact **"Probe Web Ports (80, 443, 8080–8085)"** toggle switch in `ArpControlBar` (enabled by default) plus an on-demand **"Re-Probe Ports"** button inside `ArpDetailPanel`.

---

## 3. Architecture & Model Changes

```
lib/
├── data/
│   └── services/
│       └── scanner/
│           ├── web_port_probe_service.dart       <-- [NEW] Concurrent TCP probe (80, 443, 8080-8085)
│           └── subnet_scanner_service.dart       <-- Trigger port probe for online hosts
├── domain/
│   └── models/
│       ├── open_web_port.dart                    <-- [NEW] Port number, scheme (http/https) & URL builder
│       └── arp_host_record.dart                  <-- Add List<OpenWebPort> openWebPorts
└── ui/
    └── features/
        └── scout/
            └── views/
                ├── arp_control_bar.dart          <-- Add "Web Port Probe" toggle chip
                ├── arp_table_view.dart           <-- Render clickable port pills (e.g. [80] [8080])
                └── arp_detail_panel.dart         <-- Prominent "Open Web UI (IP:Port)" action buttons
```

### 3.1 `OpenWebPort` Model (`lib/domain/models/open_web_port.dart`)
```dart
class OpenWebPort {
  final int port;
  final bool isHttps;

  const OpenWebPort({
    required this.port,
    required this.isHttps,
  });

  String get scheme => isHttps ? 'https' : 'http';

  String buildUrl(String ipAddress) {
    if ((isHttps && port == 443) || (!isHttps && port == 80)) {
      return '$scheme://$ipAddress';
    }
    return '$scheme://$ipAddress:$port';
  }

  String get displayLabel => isHttps ? 'HTTPS ($port)' : 'HTTP ($port)';
}
```

---

## 4. UI & UX Specification

1. **`ArpTableView` Inline Action Pills:**
   * Render clickable pills: **`🌐 :80`**, **`🔒 :443`**, **`🌐 :8080`**, **`🌐 :8082`**.
   * Clicking launches the default browser to that URL.
2. **`ArpDetailPanel` Browser Launch Buttons:**
   * Render full-width action buttons:
     * **`🌐 Open Web Browser — http://10.201.100.50:8080`**
     * **`🔒 Open Web Browser — https://10.201.100.50`**
   * Provide a **"Probe Ports Now"** refresh button to re-check on demand.
3. **Context Menu Actions:**
   * Dynamic **"Open Web UI (<ip>:<port>)"** entries on right-click.

---

## 5. Implementation Checklist for Agent
1. Create `OpenWebPort` model.
2. Build `WebPortProbeService` with semaphore-throttled `Socket.connect` (300ms timeout) across `[80, 443, 8080, 8081, 8082, 8083, 8084, 8085]`.
3. Wire `WebPortProbeService` into `SubnetScannerService` / `ArpScoutViewModel`.
4. Add clickable port pills in `ArpTableView` and launch buttons in `ArpDetailPanel`.
5. Add unit tests for URL formatting and mock probe responses. Verify with `flutter analyze` and `flutter test`.
