class ScanProgress {
  const ScanProgress({
    this.isScanning = false,
    this.isContinuousWatch = false,
    this.targetSubnet = '192.168.1.0/24',
    this.probedHosts = 0,
    this.totalHosts = 0,
    this.discoveredInLastSweep = 0,
    this.currentPhase = 'Idle',
    this.lastScanCompletedAt,
    this.lastError,
    this.generatedCommand = 'arp -a',
    this.watchIntervalSeconds = 15,
    this.sweepIteration = 0,
  });

  final bool isScanning;
  final bool isContinuousWatch;
  final String targetSubnet;
  final int probedHosts;
  final int totalHosts;
  final int discoveredInLastSweep;
  final String currentPhase;
  final DateTime? lastScanCompletedAt;
  final String? lastError;
  final String generatedCommand;
  final int watchIntervalSeconds;
  final int sweepIteration;

  double get progressFraction {
    if (totalHosts <= 0) return 0.0;
    return (probedHosts / totalHosts).clamp(0.0, 1.0);
  }

  ScanProgress copyWith({
    bool? isScanning,
    bool? isContinuousWatch,
    String? targetSubnet,
    int? probedHosts,
    int? totalHosts,
    int? discoveredInLastSweep,
    String? currentPhase,
    DateTime? lastScanCompletedAt,
    String? lastError,
    bool clearError = false,
    String? generatedCommand,
    int? watchIntervalSeconds,
    int? sweepIteration,
  }) {
    return ScanProgress(
      isScanning: isScanning ?? this.isScanning,
      isContinuousWatch: isContinuousWatch ?? this.isContinuousWatch,
      targetSubnet: targetSubnet ?? this.targetSubnet,
      probedHosts: probedHosts ?? this.probedHosts,
      totalHosts: totalHosts ?? this.totalHosts,
      discoveredInLastSweep:
          discoveredInLastSweep ?? this.discoveredInLastSweep,
      currentPhase: currentPhase ?? this.currentPhase,
      lastScanCompletedAt: lastScanCompletedAt ?? this.lastScanCompletedAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
      generatedCommand: generatedCommand ?? this.generatedCommand,
      watchIntervalSeconds: watchIntervalSeconds ?? this.watchIntervalSeconds,
      sweepIteration: sweepIteration ?? this.sweepIteration,
    );
  }
}
