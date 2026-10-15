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

  /// Discover the child device on the same Wi-Fi using UDP broadcast + Subnet Ping Fallback
  Future<String?> discoverChildIp({
    required String pairingCode,
    String? knownIp,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    // 1. Direct Ping on Known / Cached IP first (fastest, <200ms)
    final candidateIps = <String>{
      if (knownIp != null && knownIp.trim().isNotEmpty) knownIp.trim(),
      if (_lastDiscoveredIp != null && _lastDiscoveredIp!.trim().isNotEmpty) _lastDiscoveredIp!.trim(),
    };

    for (final ip in candidateIps) {
      if (await pingIp(ip)) {
        _lastDiscoveredIp = ip;
        return ip;
      }
    }

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
        await Future.delayed(const Duration(milliseconds: 250));
      }

      // If UDP didn't find within 1.2s, launch parallel Subnet Scan
      Future.delayed(const Duration(milliseconds: 1200), () async {
        if (!completer.isCompleted) {
          final subnetIp = await scanLocalSubnet(pairingCode);
          if (subnetIp != null && !completer.isCompleted) {
            _lastDiscoveredIp = subnetIp;
            completer.complete(subnetIp);
          }
        }
      });

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

  /// Scans local Wi-Fi subnet (/24) concurrently on port 8899 to find child when UDP is blocked by router
  Future<String?> scanLocalSubnet(String pairingCode) async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final intf in interfaces) {
        for (final addr in intf.addresses) {
          final ipStr = addr.address;
          if (ipStr.startsWith("127.") || ipStr.startsWith("169.254.")) continue;

          final parts = ipStr.split('.');
          if (parts.length != 4) continue;
          final subnetPrefix = "${parts[0]}.${parts[1]}.${parts[2]}.";

          // Generate candidate IPs (1 to 254)
          final candidates = List.generate(254, (i) => "$subnetPrefix${i + 1}");

          // Ping in parallel batches of 30 for low latency without socket exhaustion
          const batchSize = 30;
          for (int i = 0; i < candidates.length; i += batchSize) {
            final batch = candidates.sublist(
              i,
              (i + batchSize > candidates.length) ? candidates.length : (i + batchSize),
            );

            final results = await Future.wait(batch.map((ip) async {
              final ok = await pingIp(ip, timeoutMs: 350);
              return ok ? ip : null;
            }));

            final found = results.firstWhere((ip) => ip != null, orElse: () => null);
            if (found != null) {
              return found;
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Subnet scan error: $e");
    }
    return null;
  }

  /// Ping child device on port 8899 to verify it's reachable on LAN
  Future<bool> pingIp(String ip, {int timeoutMs = 1500}) async {
    try {
      final client = HttpClient()..connectionTimeout = Duration(milliseconds: timeoutMs);
      final request = await client.getUrl(Uri.parse("http://$ip:$httpPort/api/ping"));
      final response = await request.close().timeout(Duration(milliseconds: timeoutMs));
      final isOk = response.statusCode == 200;
      client.close();
      return isOk;
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

