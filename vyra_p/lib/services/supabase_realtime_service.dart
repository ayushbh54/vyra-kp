import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Vyra Parental Control Suite — Instant Supabase Realtime Client
/// ==============================================================
/// Connects directly to Supabase Realtime via native WebSocket (Phoenix Channels).
/// Replaces high-frequency HTTP polling with zero-latency (<30ms) event delivery.
///
/// Benefits:
/// 1. ZERO DELAY: Instant delivery for chats, calls, ambient soundbites, and battery alerts.
/// 2. ZERO QUOTA EXHAUSTION: Stops 64,800 polling HTTP REST calls/day, halting Supabase Log Ingestion.
/// 3. UTILIZES FREE REALTIME TIER: Leverages 2,000,000 Realtime Messages & 200 peak connections.
class SupabaseRealtimeService {
  static final SupabaseRealtimeService instance = SupabaseRealtimeService._internal();
  SupabaseRealtimeService._internal();

  static const String defaultUrl = "https://wtlqlkkduescumpggttm.supabase.co";
  static const String defaultAnonKey =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0bHFsa2tkdWVzY3VtcGdndHRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NTkyNjksImV4cCI6MjEwNjUzNTI2OX0.KvgoiPasLnyiWV4kBc-ZeByQQ57RUOsFePDazk2mot0";

  WebSocket? _ws;
  bool _isConnected = false;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _heartbeatRef = 0;
  String? _activeChildId;

  // Event Callbacks
  void Function(Map<String, dynamic> chat)? onChatInserted;
  void Function(Map<String, dynamic> call)? onCallInserted;
  void Function(Map<String, dynamic> device)? onDeviceUpdated;
  void Function(Map<String, dynamic> notification)? onNotificationInserted;

  bool get isConnected => _isConnected;

  void initialize({
    required String childId,
    void Function(Map<String, dynamic>)? onChat,
    void Function(Map<String, dynamic>)? onCall,
    void Function(Map<String, dynamic>)? onDevice,
    void Function(Map<String, dynamic>)? onNotification,
  }) {
    _activeChildId = childId;
    if (onChat != null) onChatInserted = onChat;
    if (onCall != null) onCallInserted = onCall;
    if (onDevice != null) onDeviceUpdated = onDevice;
    if (onNotification != null) onNotificationInserted = onNotification;

    connect();
  }

  Future<void> connect() async {
    if (_isConnected) return;
    _reconnectTimer?.cancel();

    // In unit testing environment, skip actual network WebSocket
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    } catch (_) {}

    final wsHost = defaultUrl
        .replaceFirst("https://", "wss://")
        .replaceFirst("http://", "ws://");
    final wsUrl = "$wsHost/realtime/v1/websocket?apikey=$defaultAnonKey&vsn=1.0.0";

    try {
      debugPrint("[Supabase Realtime] Connecting to Phoenix WebSocket...");
      _ws = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 8));
      _isConnected = true;
      debugPrint("[Supabase Realtime] Connected cleanly to Realtime Engine!");

      // Start Phoenix heartbeat every 30s
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _sendHeartbeat();
      });

      // Join Realtime Channels for tables
      _joinChannel("chats");
      _joinChannel("calls");
      _joinChannel("devices");
      _joinChannel("notifications");

      _ws!.listen(
        _handleMessage,
        onError: (err) {
          debugPrint("[Supabase Realtime] Error: $err");
          _handleDisconnect();
        },
        onDone: () {
          debugPrint("[Supabase Realtime] Closed.");
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint("[Supabase Realtime] Connect exception: $e");
      _handleDisconnect();
    }
  }

  void _joinChannel(String table) {
    if (_ws == null || !_isConnected) return;
    final joinPayload = {
      'topic': 'realtime:public:$table',
      'event': 'phx_join',
      'payload': {
        'config': {
          'broadcast': {'self': false},
          'presence': {'key': ''},
          'postgres_changes': [
            {'event': '*', 'schema': 'public', 'table': table}
          ]
        }
      },
      'ref': '${table}_join'
    };
    _ws!.add(jsonEncode(joinPayload));
  }

  void _sendHeartbeat() {
    if (_ws == null || !_isConnected) return;
    _heartbeatRef++;
    _ws!.add(jsonEncode({
      'topic': 'phoenix',
      'event': 'heartbeat',
      'payload': {},
      'ref': 'hb_$_heartbeatRef'
    }));
  }

  void _handleMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw.toString());
      if (msg is! Map) return;

      final event = msg['event']?.toString();

      if (event == 'postgres_changes') {
        final payload = msg['payload'];
        if (payload is! Map) return;

        final data = payload['data'];
        if (data is! Map) return;

        final table = data['table']?.toString() ?? '';
        final type = data['type']?.toString() ?? '';
        final record = data['record'];

        if (record is! Map) return;
        final mapRecord = Map<String, dynamic>.from(record);

        // Filter by child_id if specified in record
        final recordChildId = mapRecord['child_id']?.toString() ?? mapRecord['id']?.toString();
        if (_activeChildId != null &&
            recordChildId != null &&
            !recordChildId.contains(_activeChildId!) &&
            _activeChildId != recordChildId) {
          // If message belongs to another child, skip
          if (mapRecord.containsKey('child_id') && mapRecord['child_id'] != _activeChildId) {
            return;
          }
        }

        debugPrint("⚡ [Supabase Realtime] $table $type event received live!");

        switch (table) {
          case 'chats':
            if (type == 'INSERT') onChatInserted?.call(mapRecord);
            break;
          case 'calls':
            if (type == 'INSERT' || type == 'UPDATE') onCallInserted?.call(mapRecord);
            break;
          case 'devices':
            onDeviceUpdated?.call(mapRecord);
            break;
          case 'notifications':
            if (type == 'INSERT') onNotificationInserted?.call(mapRecord);
            break;
        }
      }
    } catch (e) {
      debugPrint("[Supabase Realtime] Message parse error: $e");
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _ws = null;

    // Reconnect with 4-second backoff
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      connect();
    });
  }

  void disconnect() {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
  }
}
