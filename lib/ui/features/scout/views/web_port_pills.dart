import 'package:material_ui/material_ui.dart';

import '../../../../domain/models/arp_host_record.dart';
import '../../../../domain/models/open_web_port.dart';

const Color webHttpPortColor = Color(0xFF38BDF8);
const Color webHttpsPortColor = Color(0xFF10B981);

/// Inline clickable web port pills (`🌐 :80`, `🔒 :443`, `🌐 :8080`) for a host.
class WebPortPills extends StatelessWidget {
  const WebPortPills({
    super.key,
    required this.record,
    required this.onOpenUrl,
  });

  final ArpHostRecord record;
  final ValueChanged<String> onOpenUrl;

  @override
  Widget build(BuildContext context) {
    if (record.openWebPorts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final port in record.openWebPorts) _buildPill(port),
      ],
    );
  }

  Widget _buildPill(OpenWebPort port) {
    final url = port.buildUrl(record.ipAddress);
    final color = port.isHttps ? webHttpsPortColor : webHttpPortColor;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: 'Open $url in browser',
        child: InkWell(
          onTap: () => onOpenUrl(url),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.7)),
            ),
            child: Text(
              port.badgeText,
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
