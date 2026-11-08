/// Model and parser for command line arguments passed to ARP Scout.
///
/// Supported flags:
/// - `--subnet <cidr>` or `--subnet=<cidr>`: Target subnet CIDR (e.g. 192.168.1.0/24).
/// - `--adapter-ip <ip>` or `--adapter-ip=<ip>`: Local network adapter IPv4 address.
/// - `--adapter-name <name>` or `--adapter-name=<name>`: Local network adapter interface name.
/// - `--target <ip>` or `--target=<ip>`: Specific destination IP.
/// - `--auto-start`: Automatically initiate subnet sweep immediately after launch.
class AppLaunchArguments {
  const AppLaunchArguments({
    this.subnet,
    this.adapterIp,
    this.adapterName,
    this.target,
    this.autoStart = false,
  });

  final String? subnet;
  final String? adapterIp;
  final String? adapterName;
  final String? target;
  final bool autoStart;

  /// Parses raw command line arguments.
  static AppLaunchArguments parse(List<String> args) {
    String? subnet;
    String? adapterIp;
    String? adapterName;
    String? target;
    bool autoStart = false;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];

      if (arg == '--subnet' && i + 1 < args.length) {
        subnet = args[++i].trim();
      } else if (arg.startsWith('--subnet=')) {
        subnet = arg.substring('--subnet='.length).trim();
      } else if (arg == '--adapter-ip' && i + 1 < args.length) {
        adapterIp = args[++i].trim();
      } else if (arg.startsWith('--adapter-ip=')) {
        adapterIp = arg.substring('--adapter-ip='.length).trim();
      } else if (arg == '--adapter-name' && i + 1 < args.length) {
        adapterName = args[++i].trim();
      } else if (arg.startsWith('--adapter-name=')) {
        adapterName = arg.substring('--adapter-name='.length).trim();
      } else if (arg == '--target' && i + 1 < args.length) {
        target = args[++i].trim();
      } else if (arg.startsWith('--target=')) {
        target = arg.substring('--target='.length).trim();
      } else if (arg == '--auto-start') {
        autoStart = true;
      }
    }

    return AppLaunchArguments(
      subnet: (subnet != null && subnet.isNotEmpty) ? subnet : null,
      adapterIp: (adapterIp != null && adapterIp.isNotEmpty) ? adapterIp : null,
      adapterName: (adapterName != null && adapterName.isNotEmpty) ? adapterName : null,
      target: (target != null && target.isNotEmpty) ? target : null,
      autoStart: autoStart,
    );
  }

  @override
  String toString() {
    return 'AppLaunchArguments(subnet: $subnet, adapterIp: $adapterIp, '
        'adapterName: $adapterName, target: $target, autoStart: $autoStart)';
  }
}
