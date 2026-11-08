import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Service managing loopback socket IPC for inter-application communication
/// with Net Route Scout (`net_route_scout`).
class InterAppIpcService {
  /// Well-known loopback IPC port for ARP Scout.
  static const int arpScoutIpcPort = 44102;

  /// Well-known loopback IPC port for Net Route Scout.
  static const int routeScoutIpcPort = 44101;

  static ServerSocket? _serverSocket;

  /// Starts listening for incoming commands on loopback IPv4 interface [port].
  ///
  /// When a message is received, [onCommand] is called with the decoded JSON map.
  static Future<ServerSocket?> startListener({
    int port = arpScoutIpcPort,
    required void Function(Map<String, dynamic> payload) onCommand,
  }) async {
    // Avoid double-binding if already active
    if (_serverSocket != null) {
      return _serverSocket;
    }

    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      _serverSocket = server;

      server.listen(
        (client) {
          client
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(
                (line) {
                  final trimmed = line.trim();
                  if (trimmed.isEmpty) return;
                  try {
                    final decoded = jsonDecode(trimmed);
                    if (decoded is Map<String, dynamic>) {
                      onCommand(decoded);
                    }
                  } catch (e) {
                    debugPrint('InterAppIpcService: failed to decode JSON payload: $e');
                  }
                },
                onError: (err) {
                  debugPrint('InterAppIpcService client error: $err');
                },
                onDone: () {
                  client.destroy();
                },
                cancelOnError: false,
              );
        },
        onError: (err) {
          debugPrint('InterAppIpcService server error: $err');
        },
      );

      return server;
    } catch (e) {
      debugPrint('InterAppIpcService: could not bind listener on port $port: $e');
      return null;
    }
  }

  /// Stops and closes the IPC listener socket if active.
  static Future<void> stopListener() async {
    try {
      await _serverSocket?.close();
    } catch (_) {}
    _serverSocket = null;
  }
}
