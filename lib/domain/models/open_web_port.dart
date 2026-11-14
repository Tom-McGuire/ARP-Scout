/// Represents an open HTTP/HTTPS web management port detected on a host.
class OpenWebPort {
  const OpenWebPort({
    required this.port,
    required this.isHttps,
  });

  final int port;
  final bool isHttps;

  String get scheme => isHttps ? 'https' : 'http';

  String buildUrl(String ipAddress) {
    if ((isHttps && port == 443) || (!isHttps && port == 80)) {
      return '$scheme://$ipAddress';
    }
    return '$scheme://$ipAddress:$port';
  }

  String get displayLabel => isHttps ? 'HTTPS ($port)' : 'HTTP ($port)';

  String get badgeText => '${isHttps ? '🔒' : '🌐'} :$port';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpenWebPort &&
          runtimeType == other.runtimeType &&
          port == other.port &&
          isHttps == other.isHttps;

  @override
  int get hashCode => Object.hash(port, isHttps);

  @override
  String toString() => 'OpenWebPort($port, isHttps: $isHttps)';
}
