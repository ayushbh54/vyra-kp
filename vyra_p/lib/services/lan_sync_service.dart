import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class LanSyncResult {
  final bool success;
  final String ip;
  final Map<String, dynamic> status;
  final List<Map<String, dynamic>> chats;
  final List<Map<String, dynamic>> calls;
  final List<Map<String, dynamic>> notifications;
  final String? errorMessage;

  LanSyncResult({
    required this.success,
    this.ip = '',
    this.status = const {},
    this.chats = const [],
    this.calls = const [],
    this.notifications = const [],
    this.errorMessage,
  });
}

class LanSyncService {
  static const int httpPort = 8899;
  static const int udpDiscoveryPort = 8898;

  String? _lastDiscoveredIp;
  String? get lastDiscoveredIp => _lastDiscoveredIp;

  /// Discover the child device on the same Wi-Fi using UDP broadcast
  Future<String?> discoverChildIp({
    required String pairingCode,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    RawDatagramSocket? socket;
    final completer = Completer<String?>();

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final message = utf8.encode("VYRA_DISCOVER:$pairingCode");
      final broadcastAddr = InternetAddress("255.255.255.255");

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null) {
            try {
              final text = utf8.decode(datagram.data).trim();
              final json = jsonDecode(text);
              if (json is Map && (json['code'] == pairingCode || json['type'] == 'VYRA_ANNOUNCE')) {
                final foundIp = json['ip']?.toString() ?? datagram.address.address;
                _lastDiscoveredIp = foundIp;
                if (!completer.isCompleted) {
                  completer.complete(foundIp);
                }
              }
            } catch (_) {}
          }
        }
      });

      // Send 3 discovery pulses
      for (int i = 0; i < 3; i++) {
        socket.send(message, broadcastAddr, udpDiscoveryPort);
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // If cached IP exists, try a direct HTTP ping
      if (_lastDiscoveredIp != null && !completer.isCompleted) {
        final ok = await pingIp(_lastDiscoveredIp!);
        if (ok && !completer.isCompleted) {
          completer.complete(_lastDiscoveredIp);
        }
      }

      Future.delayed(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(_lastDiscoveredIp);
        }
      });

      final result = await completer.future;
      socket.close();
      return result;
    } catch (e) {
      debugPrint("LAN discovery error: $e");
      socket?.close();
      return _lastDiscoveredIp;
    }
  }

  /// Ping child device on port 8899 to verify it's reachable on LAN
  Future<bool> pingIp(String ip) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(Uri.parse("http://$ip:$httpPort/api/ping"));
      final response = await request.close().timeout(const Duration(seconds: 2));
      client.close();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch full rolling database over Same-Wi-Fi direct connection
  Future<LanSyncResult> fetchFullDataOverLan(String ip) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse("http://$ip:$httpPort/api/sync"));
      final response = await request.close().timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        client.close();
        return LanSyncResult(
          success: false,
          errorMessage: "Child responded with HTTP ${response.statusCode}",
        );
      }

      final body = await response.transform(utf8.decoder).join();
      client.close();

      final data = jsonDecode(body);
      if (data is! Map) {
        return LanSyncResult(success: false, errorMessage: "Invalid payload from child");
      }

      final statusMap = (data['status'] is Map) ? Map<String, dynamic>.from(data['status']) : <String, dynamic>{};
      final chatsList = (data['chats'] is List)
          ? (data['chats'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      final callsList = (data['calls'] is List)
          ? (data['calls'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      final notifsList = (data['notifications'] is List)
          ? (data['notifications'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];

      _lastDiscoveredIp = ip;

      return LanSyncResult(
        success: true,
        ip: ip,
        status: statusMap,
        chats: chatsList,
        calls: callsList,
        notifications: notifsList,
      );
    } catch (e) {
      debugPrint("fetchFullDataOverLan error: $e");
      return LanSyncResult(success: false, errorMessage: e.toString());
    }
  }

  /// Establishes a persistent SSE stream to the child device on port 8899 (/api/stream)
  /// Pushes live chats, calls, notifications, and status sub-second in real-time.
  Stream<Map<String, dynamic>> openLiveStream(String ip) async* {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse("http://$ip:$httpPort/api/stream"));
      final response = await request.close();
      if (response.statusCode == 200) {
        yield* response
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .where((line) => line.trim().startsWith('data:'))
            .map((line) {
              final jsonStr = line.trim().substring(5).trim();
              if (jsonStr.isEmpty) return <String, dynamic>{};
              try {
                final decoded = jsonDecode(jsonStr);
                if (decoded is Map) return Map<String, dynamic>.from(decoded);
              } catch (_) {}
              return <String, dynamic>{};
            })
            .where((map) => map.isNotEmpty);
      }
    } catch (e) {
      debugPrint("LAN Live stream error: $e");
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}
    }
  }
}

