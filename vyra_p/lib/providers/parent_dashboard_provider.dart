import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_status.dart';
import '../models/child_profile.dart';
import '../models/call_record.dart';
import '../models/chat_message.dart';
import '../models/notification_item.dart';
import '../models/watchlist_target.dart';
import '../models/ambient_log_item.dart';
import '../services/audio_playback_service.dart';
import '../services/lan_sync_service.dart';
import '../services/supabase_sync_service.dart';

class ParentDashboardProvider extends ChangeNotifier {
  ParentDashboardProvider() {
    _loadLocalPersistence();
    _startLanDiscovery();
    _startSupabaseSync();
  }

  final LanSyncService _lanSync = LanSyncService();
  final SupabaseSyncService _supabaseSync = SupabaseSyncService();

  bool _isLanSyncActive = false;
  bool get isLanSyncActive => _isLanSyncActive;

  String? _lanChildIp;
  String? get lanChildIp => _lanChildIp;

  DateTime? _lastLanSyncTime;
  DateTime? get lastLanSyncTime => _lastLanSyncTime;

  bool _isLanSyncing = false;
  bool get isLanSyncing => _isLanSyncing;

  bool _isSupabaseSyncing = false;
  bool get isSupabaseSyncing => _isSupabaseSyncing;

  Timer? _lanDiscoveryTimer;
  Timer? _supabaseSyncTimer;
  StreamSubscription<Map<String, dynamic>>? _lanLiveStreamSub;

  int get totalChatsCount => _childChatMessages[_activeChildId]?.length ?? 0;
  int get totalCallsCount => _childCallRecords[_activeChildId]?.length ?? 0;
  int get totalNotifsCount => _childNotifications[_activeChildId]?.length ?? 0;

  int _todayScreenTimeMinutes = 0;
  int get todayScreenTimeMinutes => _todayScreenTimeMinutes;

  List<Map<String, dynamic>> _todayAppUsages = [];
  List<Map<String, dynamic>> get todayAppUsages => _todayAppUsages;

  static const String _defaultChildCode = 'VYRA-13533';

  // Seed default child profile so parent never has to re-type code on launch
  final List<ChildProfile> _children = [
    ChildProfile(
      id: _defaultChildCode,
      pairingCode: _defaultChildCode,
      name: 'Vivo V2404',
      deviceModel: 'Vivo V2404',
      batteryLevel: 100,
      isOnline: true,
      locationAddress: 'Linked via $_defaultChildCode',
      selectedDisguise: 'System Toolkit',
    ),
  ];
  List<ChildProfile> get children => _children;

  String _activeChildId = _defaultChildCode;
  String get activeChildId => _activeChildId;

  String get activePairingCode => _children.isEmpty ? '' : activeChild.pairingCode;

  ChildProfile get activeChild =>
      _children.firstWhere((c) => c.id == _activeChildId,
          orElse: () => _children.isNotEmpty
              ? _children.first
              : ChildProfile(
                  id: _activeChildId.isNotEmpty ? _activeChildId : 'none',
                  pairingCode: _activeChildId,
                  name: 'No Device',
                  deviceModel: 'Unknown',
                  batteryLevel: 0,
                  isOnline: false,
                  locationAddress: 'Link a child device to begin',
                  selectedDisguise: 'System Toolkit',
                ));

  Future<void> _loadLocalPersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedList = prefs.getStringList('saved_children');
      final savedActiveId = prefs.getString('active_child_id');

      if (savedList != null && savedList.isNotEmpty) {
        final loaded = <ChildProfile>[];
        for (final item in savedList) {
          try {
            final json = jsonDecode(item) as Map<String, dynamic>;
            loaded.add(ChildProfile.fromJson(json));
          } catch (_) {}
        }
        if (loaded.isNotEmpty) {
          _children.clear();
          _children.addAll(loaded);

          // Guarantee VYRA-13533 is always present in list
          if (!_children.any((c) => c.pairingCode == _defaultChildCode || c.id == _defaultChildCode)) {
            _children.insert(0, ChildProfile(
              id: _defaultChildCode,
              pairingCode: _defaultChildCode,
              name: 'Vivo V2404',
              deviceModel: 'Vivo V2404',
              batteryLevel: 100,
              isOnline: true,
              locationAddress: 'Linked via $_defaultChildCode',
              selectedDisguise: 'System Toolkit',
            ));
          }

          // Filter out obsolete test IDs (like child_1, test)
          if (savedActiveId != null &&
              savedActiveId != 'child_1' &&
              savedActiveId != 'child_2' &&
              savedActiveId != 'child_default' &&
              !savedActiveId.startsWith('test') &&
              _children.any((c) => c.id == savedActiveId)) {
            _activeChildId = savedActiveId;
          } else {
            _activeChildId = _defaultChildCode;
          }

          // Restore cached chats, calls, and notifications so data is immediately safe & visible
          final cachedChatsRaw = prefs.getStringList('cache_chats_$_activeChildId');
          if (cachedChatsRaw != null && cachedChatsRaw.isNotEmpty) {
            final restored = <ChatMessage>[];
            for (final raw in cachedChatsRaw) {
              try {
                restored.add(ChatMessage.fromJson(jsonDecode(raw)));
              } catch (_) {}
            }
            if (restored.isNotEmpty) {
              _childChatMessages[_activeChildId] = restored;
              _mergeNotificationsIntoActiveChats();
            }
          }

          final cachedCallsRaw = prefs.getStringList('cache_calls_$_activeChildId');
          if (cachedCallsRaw != null && cachedCallsRaw.isNotEmpty) {
            final restored = <CallRecord>[];
            for (final raw in cachedCallsRaw) {
              try {
                restored.add(CallRecord.fromJson(jsonDecode(raw)));
              } catch (_) {}
            }
            if (restored.isNotEmpty) {
              _childCallRecords[_activeChildId] = restored;
            }
          }

          final cachedNotifsRaw = prefs.getStringList('cache_notifs_$_activeChildId');
          if (cachedNotifsRaw != null && cachedNotifsRaw.isNotEmpty) {
            final restored = <NotificationItem>[];
            for (final raw in cachedNotifsRaw) {
              try {
                restored.add(NotificationItem.fromJson(jsonDecode(raw)));
              } catch (_) {}
            }
            if (restored.isNotEmpty) {
              _childNotifications[_activeChildId] = restored;
            }
          }

          syncFromSupabase();
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("Load persistence error: $e");
    }
  }

  Future<void> _saveLocalPersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _children.map((c) => jsonEncode(c.toJson())).toList();
      await prefs.setStringList('saved_children', list);
      await prefs.setString('active_child_id', _activeChildId);

      // Persist active child data to local disk (capped to recent 2,000 chats so SharedPreferences stays fast)
      final msgs = _childChatMessages[_activeChildId];
      if (msgs != null && msgs.isNotEmpty) {
        final raw = msgs.take(2000).map((m) => jsonEncode(m.toJson())).toList();
        await prefs.setStringList('cache_chats_$_activeChildId', raw);
      }

      final calls = _childCallRecords[_activeChildId];
      if (calls != null && calls.isNotEmpty) {
        final raw = calls.take(1000).map((c) => jsonEncode(c.toJson())).toList();
        await prefs.setStringList('cache_calls_$_activeChildId', raw);
      }

      final notifs = _childNotifications[_activeChildId];
      if (notifs != null && notifs.isNotEmpty) {
        final raw = notifs.take(1000).map((n) => jsonEncode(n.toJson())).toList();
        await prefs.setStringList('cache_notifs_$_activeChildId', raw);
      }
    } catch (e) {
      debugPrint("Save persistence error: $e");
    }
  }

  void _startLanDiscovery() {
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    } catch (_) {}
    _lanDiscoveryTimer?.cancel();
    // Periodically pulse on local Wi-Fi every 25 seconds
    _lanDiscoveryTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      triggerLanSync();
    });
    // First trigger after 3s
    Future.delayed(const Duration(seconds: 3), () => triggerLanSync());
  }

  /// Direct Same-Wi-Fi Sync (Zero Cloud Quota, Instant Real-Time Transfer)
  Future<bool> triggerLanSync({bool showFeedback = false}) async {
    if (_isLanSyncing) return false;
    _isLanSyncing = true;
    notifyListeners();

    try {
      final targetCode = activePairingCode.isNotEmpty ? activePairingCode : _activeChildId;
      final ip = await _lanSync.discoverChildIp(pairingCode: targetCode);

      if (ip == null || ip.isEmpty) {
        _isLanSyncing = false;
        notifyListeners();
        return false;
      }

      final result = await _lanSync.fetchFullDataOverLan(ip);
      if (!result.success) {
        _isLanSyncing = false;
        notifyListeners();
        return false;
      }

      // 1. Update Telemetry
      if (result.status.isNotEmpty) {
        final idx = _children.indexWhere((c) => c.id == _activeChildId);
        if (idx != -1) {
          final s = result.status;
          _children[idx] = ChildProfile(
            id: _activeChildId,
            pairingCode: _children[idx].pairingCode,
            name: s['name'] ?? _children[idx].name,
            deviceModel: s['deviceModel'] ?? _children[idx].deviceModel,
            batteryLevel: (s['batteryLevel'] as num?)?.toInt() ?? _children[idx].batteryLevel,
            isOnline: true,
            locationAddress: s['locationAddress'] ?? _children[idx].locationAddress,
            selectedDisguise: s['selectedDisguise'] ?? _children[idx].selectedDisguise,
            isScreenOn: s['isScreenOn'] as bool? ?? _children[idx].isScreenOn,
          );
        }
      }

      // 2. Merge Chats
      if (result.chats.isNotEmpty) {
        final newMsgs = <ChatMessage>[];
        for (final m in result.chats) {
          final id = m['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final rawText = m['text']?.toString() ?? '';
          if (isScraperGarbage(rawText)) continue;

          final appStr = (m['app'] ?? '').toString().toLowerCase();
          AppType app = AppType.whatsApp;
          if (appStr.contains('insta')) app = AppType.instagram;
          if (appStr.contains('tele')) app = AppType.telegram;
          if (appStr.contains('snap')) app = AppType.snapchat;
          if (appStr.contains('sms')) app = AppType.sms;

          final dt = m['timestampMs'] != null
              ? DateTime.fromMillisecondsSinceEpoch((m['timestampMs'] as num).toInt())
              : DateTime.now();

          final rawSender = m['sender']?.toString() ?? 'Unknown';
          final parsed = parseMessageContent(rawSender, rawText, m['isDeletedBySender'] as bool? ?? false);
          final cleanSender = normalizeContactName(parsed.sender);
          final isTarget = isWatchlistContact(cleanSender) || (m['isWatchlistTarget'] as bool? ?? false);
          newMsgs.add(ChatMessage(
            id: id,
            appType: app,
            contactName: cleanSender,
            contactIdentifier: isWatchlistContact(cleanSender) ? '@harshit_kamboj97' : cleanSender,
            messageText: parsed.cleanText,
            timestamp: dt,
            isIncoming: (m['isIncoming'] as bool?) ?? true,
            isDeletedBackup: parsed.isDeleted,
            isWatchlistTarget: isTarget,
            mediaUrl: m['mediaUrl']?.toString(),
            mediaType: m['mediaType']?.toString(),
            isViewOnce: (m['isViewOnce'] as bool?) ?? false,
          ));
        }

        _childChatMessages.putIfAbsent(_activeChildId, () => []);
        final existingIds = _childChatMessages[_activeChildId]!.map((e) => e.id).toSet();
        for (final msg in newMsgs) {
          if (!existingIds.contains(msg.id)) {
            _childChatMessages[_activeChildId]!.insert(0, msg);
          }
        }
        _mergeNotificationsIntoActiveChats();
      }

      // 3. Merge Calls & Ambient Logs
      if (result.calls.isNotEmpty) {
        final newCalls = <CallRecord>[];
        final newAmbient = <AmbientLogItem>[];
        for (final c in result.calls) {
          final id = c['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final dt = c['timestampMs'] != null
              ? DateTime.fromMillisecondsSinceEpoch((c['timestampMs'] as num).toInt())
              : (c['timestamp'] != null
                  ? DateTime.fromMillisecondsSinceEpoch((c['timestamp'] as num).toInt())
                  : DateTime.now());

          final contactName = (c['contactName'] ?? c['contact'] ?? 'Unknown').toString();
          final phoneNumber = (c['phoneNumber'] ?? '').toString();
          final durationSecs = ((c['durationSeconds'] ?? c['duration']) as num?)?.toInt() ?? 0;
          final recUrl = c['recordingUrl']?.toString();

          if (isAmbientVoiceRecord(id, contactName, phoneNumber)) {
            newAmbient.add(AmbientLogItem(
              id: id,
              timestamp: dt,
              durationSeconds: durationSecs,
              audioUrl: (recUrl != null && recUrl.trim().isNotEmpty) ? recUrl : null,
              locationContext: phoneNumber.isNotEmpty ? phoneNumber : 'Pocket Mic (Screen-Off)',
              speechSnippet: contactName,
              isPurgedFromCloud: recUrl == null || recUrl.trim().isEmpty,
              storageFreedKb: 1850,
              conversationSummary: 'Ambient voice activity logged while screen was off.',
            ));
          } else {
            newCalls.add(CallRecord(
              id: id,
              contactName: contactName,
              phoneNumber: phoneNumber,
              callType: CallType.incoming,
              timestamp: dt,
              durationSeconds: durationSecs,
              recordingUrl: recUrl,
              isTamperAttemptDetected: c['isTamperAttemptDetected'] as bool? ?? false,
              isWatchlistTarget: isWatchlistContact(contactName),
            ));
          }
        }
        if (newCalls.isNotEmpty) {
          _childCallRecords.putIfAbsent(_activeChildId, () => []);
          final existingCallIds = _childCallRecords[_activeChildId]!.map((e) => e.id).toSet();
          for (final call in newCalls) {
            if (!existingCallIds.contains(call.id)) {
              _childCallRecords[_activeChildId]!.insert(0, call);
            }
          }
        }
        if (newAmbient.isNotEmpty) {
          _childAmbientLogs.putIfAbsent(_activeChildId, () => []);
          final existingAmbIds = _childAmbientLogs[_activeChildId]!.map((e) => e.id).toSet();
          for (final amb in newAmbient) {
            if (!existingAmbIds.contains(amb.id)) {
              _childAmbientLogs[_activeChildId]!.insert(0, amb);
            }
          }
          _childAmbientLogs[_activeChildId]!.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        }
      }

      // 4. Merge Notifications
      if (result.notifications.isNotEmpty) {
        final newNotifs = <NotificationItem>[];
        for (final n in result.notifications) {
          final id = n['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final dt = n['timestampMs'] != null
              ? DateTime.fromMillisecondsSinceEpoch((n['timestampMs'] as num).toInt())
              : DateTime.now();

          newNotifs.add(NotificationItem(
            id: id,
            packageName: n['packageName']?.toString() ?? '',
            appName: n['appName']?.toString() ?? 'App',
            title: n['title']?.toString() ?? '',
            message: n['text']?.toString() ?? '',
            timestamp: dt,
            isSensitiveAlert: n['isImportant'] as bool? ?? false,
          ));
        }
        _childNotifications.putIfAbsent(_activeChildId, () => []);
        final existingNotifIds = _childNotifications[_activeChildId]!.map((e) => e.id).toSet();
        for (final notif in newNotifs) {
          if (!existingNotifIds.contains(notif.id)) {
            _childNotifications[_activeChildId]!.insert(0, notif);
          }
        }
      }

      _childChatMessages[_activeChildId]?.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _childCallRecords[_activeChildId]?.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _childNotifications[_activeChildId]?.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      _isLanSyncActive = true;
      _lanChildIp = ip;
      _lastLanSyncTime = DateTime.now();
      _isLanSyncing = false;
      _saveLocalPersistence();
      notifyListeners();

      if (_lanLiveStreamSub == null) {
        _subscribeToLiveLanStream(ip);
      }
      return true;
    } catch (e) {
      debugPrint("triggerLanSync error: $e");
      _isLanSyncing = false;
      notifyListeners();
      return false;
    }
  }

  void _subscribeToLiveLanStream(String ip) {
    _lanLiveStreamSub?.cancel();
    _lanLiveStreamSub = _lanSync.openLiveStream(ip).listen((event) {
      final type = event['type']?.toString();
      final data = event['data'];
      if (data is! Map) return;
      final m = Map<String, dynamic>.from(data);

      if (type == 'chat') {
        _handleLiveChatEvent(m);
      } else if (type == 'call') {
        _handleLiveCallEvent(m);
      } else if (type == 'notification') {
        _handleLiveNotificationEvent(m);
      } else if (type == 'status') {
        _handleLiveStatusEvent(m);
      }
    }, onError: (e) {
      debugPrint("LAN Live stream disconnected: $e");
      _lanLiveStreamSub = null;
    }, onDone: () {
      debugPrint("LAN Live stream completed");
      _lanLiveStreamSub = null;
    });
  }

  void _handleLiveChatEvent(Map<String, dynamic> m) {
    final id = m['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final appStr = (m['app'] ?? '').toString().toLowerCase();
    AppType app = AppType.whatsApp;
    if (appStr.contains('insta')) app = AppType.instagram;
    if (appStr.contains('tele')) app = AppType.telegram;
    if (appStr.contains('snap')) app = AppType.snapchat;
    if (appStr.contains('sms')) app = AppType.sms;

    final dt = m['timestampMs'] != null
        ? DateTime.fromMillisecondsSinceEpoch((m['timestampMs'] as num).toInt())
        : DateTime.now();

    final rawSender = m['sender']?.toString() ?? 'Unknown';
    final cleanSender = normalizeContactName(rawSender);
    final isTarget = isWatchlistContact(cleanSender) || (m['isWatchlistTarget'] as bool? ?? false);
    final newMsg = ChatMessage(
      id: id,
      appType: app,
      contactName: cleanSender,
      contactIdentifier: cleanSender,
      messageText: m['text']?.toString() ?? '',
      timestamp: dt,
      isIncoming: (m['isIncoming'] as bool?) ?? true,
      isDeletedBackup: m['isDeletedBySender'] as bool? ?? false,
      isWatchlistTarget: isTarget,
    );

    _childChatMessages.putIfAbsent(_activeChildId, () => []);
    final exists = _childChatMessages[_activeChildId]!.any((x) => x.id == id);
    if (!exists) {
      _childChatMessages[_activeChildId]!.insert(0, newMsg);
      _mergeNotificationsIntoActiveChats();
      _saveLocalPersistence();
      notifyListeners();
    }
  }

  void _handleLiveCallEvent(Map<String, dynamic> c) {
    final id = c['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final dt = c['timestampMs'] != null
        ? DateTime.fromMillisecondsSinceEpoch((c['timestampMs'] as num).toInt())
        : (c['timestamp'] != null
            ? DateTime.fromMillisecondsSinceEpoch((c['timestamp'] as num).toInt())
            : DateTime.now());

    final contactName = (c['contactName'] ?? c['contact'] ?? 'Unknown').toString();
    final phoneNumber = (c['phoneNumber'] ?? '').toString();
    final durationSecs = ((c['durationSeconds'] ?? c['duration']) as num?)?.toInt() ?? 0;
    final recUrl = c['recordingUrl']?.toString();

    if (isAmbientVoiceRecord(id, contactName, phoneNumber)) {
      final amb = AmbientLogItem(
        id: id,
        timestamp: dt,
        durationSeconds: durationSecs,
        audioUrl: (recUrl != null && recUrl.trim().isNotEmpty) ? recUrl : null,
        locationContext: phoneNumber.isNotEmpty ? phoneNumber : 'Pocket Mic (Screen-Off)',
        speechSnippet: contactName,
        isPurgedFromCloud: recUrl == null || recUrl.trim().isEmpty,
        storageFreedKb: 1850,
        conversationSummary: 'Ambient voice activity logged while screen was off.',
      );
      _childAmbientLogs.putIfAbsent(_activeChildId, () => []);
      if (!_childAmbientLogs[_activeChildId]!.any((x) => x.id == id)) {
        _childAmbientLogs[_activeChildId]!.insert(0, amb);
        notifyListeners();
      }
      return;
    }

    final newCall = CallRecord(
      id: id,
      contactName: contactName,
      phoneNumber: phoneNumber,
      callType: CallType.incoming,
      timestamp: dt,
      durationSeconds: durationSecs,
      recordingUrl: recUrl,
      isTamperAttemptDetected: c['isTamperAttemptDetected'] as bool? ?? false,
      isWatchlistTarget: isWatchlistContact(contactName),
    );

    _childCallRecords.putIfAbsent(_activeChildId, () => []);
    final exists = _childCallRecords[_activeChildId]!.any((x) => x.id == id);
    if (!exists) {
      _childCallRecords[_activeChildId]!.insert(0, newCall);
      _saveLocalPersistence();
      notifyListeners();
    }
  }

  void _handleLiveNotificationEvent(Map<String, dynamic> n) {
    final id = n['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final dt = n['timestampMs'] != null
        ? DateTime.fromMillisecondsSinceEpoch((n['timestampMs'] as num).toInt())
        : DateTime.now();

    final newNotif = NotificationItem(
      id: id,
      packageName: n['packageName']?.toString() ?? '',
      appName: n['appName']?.toString() ?? 'App',
      title: n['title']?.toString() ?? '',
      message: n['text']?.toString() ?? '',
      timestamp: dt,
      isSensitiveAlert: n['isImportant'] as bool? ?? false,
    );

    _childNotifications.putIfAbsent(_activeChildId, () => []);
    final exists = _childNotifications[_activeChildId]!.any((x) => x.id == id);
    if (!exists) {
      _childNotifications[_activeChildId]!.insert(0, newNotif);
      _mergeNotificationsIntoActiveChats();
      _saveLocalPersistence();
      notifyListeners();
    }
  }

  void _handleLiveStatusEvent(Map<String, dynamic> s) {
    final idx = _children.indexWhere((c) => c.id == _activeChildId);
    if (idx != -1) {
      _children[idx] = ChildProfile(
        id: _activeChildId,
        pairingCode: _children[idx].pairingCode,
        name: s['name'] ?? _children[idx].name,
        deviceModel: s['deviceModel'] ?? _children[idx].deviceModel,
        batteryLevel: (s['batteryLevel'] as num?)?.toInt() ?? _children[idx].batteryLevel,
        isOnline: true,
        locationAddress: s['locationAddress'] ?? _children[idx].locationAddress,
        selectedDisguise: s['selectedDisguise'] ?? _children[idx].selectedDisguise,
        isScreenOn: s['isScreenOn'] as bool? ?? _children[idx].isScreenOn,
      );
      _lastLanSyncTime = DateTime.now();
      _isLanSyncActive = true;
      _saveLocalPersistence();
      notifyListeners();
    }
  }

  void _startSupabaseSync() {
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    } catch (_) {}
    _supabaseSyncTimer?.cancel();
    _supabaseSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      syncFromSupabase();
    });
    // First trigger after 1.5 seconds
    Future.delayed(const Duration(milliseconds: 1500), () => syncFromSupabase());
  }

  Future<void> refreshAll() async {
    await Future.wait([
      syncFromSupabase(),
      triggerLanSync(),
    ]);
  }

  /// Supabase Cloud Sync: Fetches devices, calls/ambient logs, notifications, screen time, and chats
  /// from Supabase PostgreSQL tables and seamlessly merges them into local memory and disk persistence cache.
  Future<void> syncFromSupabase({int? chatLimit}) async {
    if (!_supabaseSync.isConfigured) return;
    if (_isSupabaseSyncing) return;
    _isSupabaseSyncing = true;
    notifyListeners();

    final targetCode = activePairingCode.isNotEmpty ? activePairingCode : _activeChildId;

    try {
      // 1. Fetch Devices & Telemetry FIRST (fast, <200ms)
      final devices = await _supabaseSync.fetchTable("devices");
      if (devices.isNotEmpty) {
        for (final d in devices) {
          final devId = d['id']?.toString() ?? '';
          if (devId.isEmpty) continue;

          final idx = _children.indexWhere((c) => c.id == devId || c.pairingCode == devId);
          if (idx != -1) {
            _children[idx] = ChildProfile(
              id: _children[idx].id,
              pairingCode: _children[idx].pairingCode,
              name: (_children[idx].name.isEmpty || _children[idx].name == 'No Device')
                  ? (d['device_model'] ?? 'Vivo V2404')
                  : _children[idx].name,
              deviceModel: d['device_model']?.toString() ?? _children[idx].deviceModel,
              batteryLevel: (d['battery_level'] as num?)?.toInt() ?? _children[idx].batteryLevel,
              isOnline: (d['is_online'] as bool?) ?? _children[idx].isOnline,
              locationAddress: d['location_address']?.toString() ?? _children[idx].locationAddress,
              selectedDisguise: d['selected_disguise']?.toString() ?? _children[idx].selectedDisguise,
              isScreenOn: (d['is_screen_on'] as bool?) ?? _children[idx].isScreenOn,
            );
          } else {
            _children.add(ChildProfile(
              id: devId,
              pairingCode: devId,
              name: d['device_model']?.toString() ?? 'Child Device',
              deviceModel: d['device_model']?.toString() ?? 'Android Phone',
              batteryLevel: (d['battery_level'] as num?)?.toInt() ?? 100,
              isOnline: (d['is_online'] as bool?) ?? true,
              locationAddress: d['location_address']?.toString() ?? '',
              selectedDisguise: d['selected_disguise']?.toString() ?? 'System Toolkit',
              isScreenOn: (d['is_screen_on'] as bool?) ?? false,
            ));
          }
        }
      }

      // 2. Fetch Calls & Ambient Voice Logs SECOND (1,465 rows -> 225 calls + 1,240 ambient logs)
      final callsData = await _supabaseSync.fetchTable(
        "calls",
        filterField: "child_id",
        filterValue: targetCode,
        order: "timestamp_ms.desc",
      );
      if (callsData.isNotEmpty) {
        final newCalls = <CallRecord>[];
        final newAmbient = <AmbientLogItem>[];
        for (final c in callsData) {
          final id = c['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final dt = c['timestamp_ms'] != null
              ? DateTime.fromMillisecondsSinceEpoch((c['timestamp_ms'] as num).toInt())
              : DateTime.now();

          final contactName = c['contact_name']?.toString() ?? 'Unknown';
          final phoneNumber = c['phone_number']?.toString() ?? '';
          final durationSecs = (c['duration_seconds'] as num?)?.toInt() ?? 0;
          final recUrl = c['recording_url']?.toString();
          final isTarget = isWatchlistContact(contactName) || ((c['is_watchlist_target'] as bool?) ?? false);

          if (isAmbientVoiceRecord(id, contactName, phoneNumber)) {
            newAmbient.add(AmbientLogItem(
              id: id,
              timestamp: dt,
              durationSeconds: durationSecs,
              audioUrl: (recUrl != null && recUrl.trim().isNotEmpty) ? recUrl : null,
              locationContext: phoneNumber.isNotEmpty ? phoneNumber : 'Pocket Mic (Screen-Off)',
              speechSnippet: contactName.isNotEmpty ? contactName : 'Ambient Voice Log',
              isFlagged: isTarget,
              isPurgedFromCloud: recUrl == null || recUrl.trim().isEmpty,
              storageFreedKb: 1850,
              conversationSummary: (recUrl != null && recUrl.trim().isNotEmpty)
                  ? 'Ambient audio soundbite captured while screen was off.'
                  : 'Ambient voice activity logged while screen was off (Pocket Mic).',
            ));
          } else {
            final typeStr = (c['call_type'] ?? 'incoming').toString().toLowerCase();
            CallType cType = CallType.incoming;
            if (typeStr.contains('out')) cType = CallType.outgoing;
            if (typeStr.contains('miss')) cType = CallType.missed;

            newCalls.add(CallRecord(
              id: id,
              contactName: contactName,
              phoneNumber: phoneNumber,
              callType: cType,
              timestamp: dt,
              durationSeconds: durationSecs,
              recordingUrl: recUrl,
              recordingDurationSeconds: (c['recording_duration_seconds'] as num?)?.toInt(),
              isTamperAttemptDetected: (c['is_tamper_attempt_detected'] as bool?) ?? false,
              isWatchlistTarget: isTarget,
            ));
          }
        }

        if (newCalls.isNotEmpty) {
          _childCallRecords.putIfAbsent(_activeChildId, () => []);
          // Also remove any previously misclassified ambient_* items from _childCallRecords
          _childCallRecords[_activeChildId]!.removeWhere(
            (r) => isAmbientVoiceRecord(r.id, r.contactName, r.phoneNumber),
          );
          final existingCallIds = _childCallRecords[_activeChildId]!.map((e) => e.id).toSet();
          for (final call in newCalls) {
            if (!existingCallIds.contains(call.id)) {
              _childCallRecords[_activeChildId]!.add(call);
            }
          }
          _childCallRecords[_activeChildId]!.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        }

        if (newAmbient.isNotEmpty) {
          _childAmbientLogs.putIfAbsent(_activeChildId, () => []);
          final existingAmbIds = _childAmbientLogs[_activeChildId]!.map((e) => e.id).toSet();
          for (final amb in newAmbient) {
            if (!existingAmbIds.contains(amb.id)) {
              _childAmbientLogs[_activeChildId]!.add(amb);
            }
          }
          _childAmbientLogs[_activeChildId]!.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        }
      }

      // 3. Fetch Notifications THIRD
      final notifsData = await _supabaseSync.fetchTable(
        "notifications",
        filterField: "child_id",
        filterValue: targetCode,
        order: "timestamp_ms.desc",
        limit: (_childNotifications[_activeChildId]?.isNotEmpty ?? false) ? 1000 : 5000,
      );
      if (notifsData.isNotEmpty) {
        final newNotifs = <NotificationItem>[];
        for (final n in notifsData) {
          final id = n['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final dt = n['timestamp_ms'] != null
              ? DateTime.fromMillisecondsSinceEpoch((n['timestamp_ms'] as num).toInt())
              : DateTime.now();

          newNotifs.add(NotificationItem(
            id: id,
            packageName: n['package_name']?.toString() ?? '',
            appName: n['app_name']?.toString() ?? 'App',
            title: n['title']?.toString() ?? '',
            message: n['text']?.toString() ?? '',
            timestamp: dt,
            isSensitiveAlert: (n['is_important'] as bool?) ?? false,
          ));
        }

        _childNotifications.putIfAbsent(_activeChildId, () => []);
        final existingNotifIds = _childNotifications[_activeChildId]!.map((e) => e.id).toSet();
        for (final notif in newNotifs) {
          if (!existingNotifIds.contains(notif.id)) {
            _childNotifications[_activeChildId]!.add(notif);
          }
        }
        _childNotifications[_activeChildId]!.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }

      // 4. Fetch Screen Time FOURTH
      final screenTimeData = await _supabaseSync.fetchTable(
        "screen_time",
        filterField: "child_id",
        filterValue: targetCode,
        order: "timestamp_ms.desc",
        limit: 1,
      );
      if (screenTimeData.isNotEmpty) {
        final st = screenTimeData.first;
        _todayScreenTimeMinutes = (st['total_screen_time_minutes'] as num?)?.toInt() ?? 0;
        final rawApps = st['apps'];
        if (rawApps is List) {
          _todayAppUsages = rawApps.map((a) {
            final m = a as Map<String, dynamic>;
            return {
              'appName': m['appName']?.toString() ?? 'App',
              'packageName': m['packageName']?.toString() ?? '',
              'minutes': (m['minutes'] as num?)?.toInt() ?? 0,
              'lastUsed': (m['lastUsed'] as num?)?.toInt() ?? 0,
            };
          }).toList();
        }
      }

      // Notify UI immediately once fast telemetry, calls, ambient logs, notifications & screen time are ready!
      notifyListeners();

      // 5. Fetch Chats (Windowed so 276,157 archived rows never stall UI or exhaust RAM)
      final hasLoadedChats = _childChatMessages[_activeChildId]?.isNotEmpty ?? false;
      final effectiveChatLimit = chatLimit ?? (hasLoadedChats ? 1000 : 3000);
      final chatsData = await _supabaseSync.fetchTable(
        "chats",
        filterField: "child_id",
        filterValue: targetCode,
        order: "timestamp_ms.desc",
        limit: effectiveChatLimit,
      );
      if (chatsData.isNotEmpty) {
        final newMsgs = <ChatMessage>[];
        for (final m in chatsData) {
          final id = m['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final rawText = m['text']?.toString() ?? '';
          if (isScraperGarbage(rawText)) continue;

          final appStr = (m['app'] ?? '').toString().toLowerCase();
          AppType app = AppType.whatsApp;
          if (appStr.contains('insta')) app = AppType.instagram;
          if (appStr.contains('tele')) app = AppType.telegram;
          if (appStr.contains('snap')) app = AppType.snapchat;
          if (appStr.contains('sms') || appStr.contains('mms')) app = AppType.sms;

          final dt = m['timestamp_ms'] != null
              ? DateTime.fromMillisecondsSinceEpoch((m['timestamp_ms'] as num).toInt())
              : DateTime.now();

          final rawSender = m['sender']?.toString() ?? 'Unknown';
          final rawDeleted = (m['is_deleted_by_sender'] as bool?) ?? false;
          final parsed = parseMessageContent(rawSender, rawText, rawDeleted);
          final cleanSender = normalizeContactName(parsed.sender);
          final isTarget = isWatchlistContact(cleanSender) || ((m['is_watchlist_target'] as bool?) ?? false);

          newMsgs.add(ChatMessage(
            id: id,
            appType: app,
            contactName: cleanSender,
            contactIdentifier: isWatchlistContact(cleanSender) ? '@harshit_kamboj97' : cleanSender,
            messageText: parsed.cleanText,
            timestamp: dt,
            isIncoming: (m['is_incoming'] as bool?) ?? true,
            isDeletedBackup: parsed.isDeleted,
            isWatchlistTarget: isTarget,
            mediaUrl: m['media_url']?.toString(),
            mediaType: m['media_type']?.toString(),
            isViewOnce: (m['is_view_once'] as bool?) ?? false,
          ));
        }

        _childChatMessages.putIfAbsent(_activeChildId, () => []);
        final existingIds = _childChatMessages[_activeChildId]!.map((e) => e.id).toSet();
        for (final msg in newMsgs) {
          if (!existingIds.contains(msg.id)) {
            _childChatMessages[_activeChildId]!.add(msg);
          }
        }
        _childChatMessages[_activeChildId]!.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _mergeNotificationsIntoActiveChats();
      }

      _saveLocalPersistence();
    } catch (e) {
      debugPrint("syncFromSupabase error: $e");
    } finally {
      _isSupabaseSyncing = false;
      notifyListeners();
    }
  }

  /// Purges past records from Supabase Cloud to free up storage space.
  /// Crucially preserves parent phone's local disk cache so offline data is never lost!
  Future<bool> purgeSupabaseCloudStorage({bool preserveLocalCache = true}) async {
    final targetCode = activePairingCode.isNotEmpty ? activePairingCode : _activeChildId;
    final success = await _supabaseSync.purgeChildCloudHistory(targetCode);
    if (success) {
      debugPrint("Supabase cloud history purged successfully for $targetCode");
      notifyListeners();
    }
    return success;
  }

  void switchChild(String childId) {
    if (_activeChildId == childId) return; // Prevent redundant refetching
    _activeChildId = childId;
    _saveLocalPersistence();
    syncFromSupabase();
    notifyListeners();
  }

  ChildProfile addNewChild({
    required String name,
    String? deviceModel,
    String? customCode,
  }) {
    final code = (customCode != null && customCode.trim().isNotEmpty)
        ? customCode.trim().toUpperCase()
        : _generateUniquePairingCode();
    final newId = "child_${DateTime.now().millisecondsSinceEpoch}";
    final newChild = ChildProfile(
      id: newId,
      pairingCode: code,
      name: name.trim(),
      deviceModel: (deviceModel != null && deviceModel.trim().isNotEmpty)
          ? deviceModel.trim()
          : "Android Phone",
      batteryLevel: 100,
      isOnline: true,
      locationAddress: "Waiting for device setup...",
      selectedDisguise: "System Toolkit",
    );
    _children.add(newChild);
    _childCallRecords[newId] = [];
    _childChatMessages[newId] = [];
    _childAmbientLogs[newId] = [];
    _childNotifications[newId] = [];
    _childWatchlists[newId] = [];
    _activeChildId = newId;
    _saveLocalPersistence();
    notifyListeners();
    return newChild;
  }

  String _generateUniquePairingCode() {
    final rand = 1000 + (DateTime.now().millisecondsSinceEpoch % 9000);
    return 'VYRA-$rand';
  }

  ChildProfile linkChildWithCode(String code, {String? name}) {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) return activeChild;

    final existingIdx = _children.indexWhere((c) => c.id == cleanCode || c.pairingCode == cleanCode);
    if (existingIdx != -1) {
      if (name != null && name.trim().isNotEmpty) {
        _children[existingIdx] = _children[existingIdx].copyWith(name: name.trim());
      }
      final shouldSwitch = _activeChildId != _children[existingIdx].id;
      if (shouldSwitch) {
        _activeChildId = _children[existingIdx].id;
      }
      _saveLocalPersistence();
      notifyListeners();
      return _children[existingIdx];
    } else {
      final newChild = ChildProfile(
        id: cleanCode,
        pairingCode: cleanCode,
        name: name ?? "Child Device ($cleanCode)",
        deviceModel: "Android Phone",
        batteryLevel: 100,
        isOnline: true,
        locationAddress: "Connected via $cleanCode",
        selectedDisguise: "System Toolkit",
      );
      _children.add(newChild);
      _childCallRecords[cleanCode] = [];
      _childChatMessages[cleanCode] = [];
      _childAmbientLogs[cleanCode] = [];
      _childNotifications[cleanCode] = [];
      _childWatchlists[cleanCode] = [];
      _activeChildId = cleanCode;
      _saveLocalPersistence();
      notifyListeners();
      return newChild;
    }
  }

  static bool isScraperGarbage(String text) {
    final t = text.trim();
    if (t.length < 2) return true;

    // View / Resource IDs (e.g. 2131232237)
    if (RegExp(r'^\d{6,}$').hasMatch(t)) return true;

    final lower = t.toLowerCase();

    // End-to-end encryption notices and security disclaimers
    if (lower.contains('end-to-end encrypted') ||
        lower.contains('end to end encrypted') ||
        lower.contains('messages and calls are end-to-end') ||
        lower.contains('your personal messages are end-to-end')) {
      return true;
    }

    // Android Action Buttons, quick actions, dialog buttons
    const actionButtons = {
      'copy',
      'copy code',
      'copy otp',
      'tap to copy',
      'reply',
      'delete',
      'delete message',
      'forward',
      'share',
      'mark as read',
      'clear all',
      'dismiss',
      'view details',
      'report',
      'block',
      'done',
      'cancel',
      'install',
      'update',
      'open',
      'messages',
      'all messages',
      'conversations',
      'select',
      'select all',
      'unread',
      'read',
    };
    if (actionButtons.contains(lower)) return true;

    // Relative timestamps: "6 minutes ago", "12 mins ago", "2 hours ago", "yesterday", "just now", "10:30 AM"
    if (RegExp(r'^\d+\s*(?:second|sec|minute|min|hour|hr|day|week|month)s?\s*(?:ago)?$', caseSensitive: false).hasMatch(t)) {
      return true;
    }
    if (lower == 'just now' || lower == 'today' || lower == 'yesterday' || lower == 'yesterday at' || lower == 'now') {
      return true;
    }
    if (RegExp(r'^\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)?$').hasMatch(t)) return true;
    if (RegExp(r'^\d{1,2}/\d{1,2}/\d{2,4}$').hasMatch(t)) return true;

    // Standalone SMS sender codes (e.g. "JK-UNIONB-S", "VK-HDFCBK") when scraped as separate text views
    if (RegExp(r'^[A-Z]{2}-[A-Z0-9]{4,10}$', caseSensitive: false).hasMatch(t)) {
      return true;
    }

    // Standalone OTP digits (e.g. "188 761" or 4-8 isolated digits)
    if (RegExp(r'^\d{3}\s+\d{3}$').hasMatch(t)) return true;
    if (RegExp(r'^\d{4,8}$').hasMatch(t)) return true;

    // Notification subheaders and tags
    if (lower.startsWith('otp •') || lower.startsWith('otp:') || lower == 'otp' || lower.contains('transaction alert')) {
      return true;
    }

    const garbageIds = {
      'feed_plus_badge_icon',
      'avatar_container',
      'action_bar_root',
      'icon_placeholder',
      'status_bar_latest_event_content',
      'action_bar',
      'navigation_bar_item_labels_group',
      'action_mode_close_button',
    };
    if (garbageIds.contains(lower)) return true;

    // Static UI action bar buttons and navigation placeholders that get scraped
    const uiNavigationGarbage = {
      'ask meta ai or search',
      'search',
      'search...',
      'phone',
      'video call',
      'voice call',
      'camera',
      'more options',
      'back',
      'type a message',
      'message',
      'message...',
      'send',
      'stickers',
      'emoji',
      'attach',
      'disappearing messages',
      'chat',
      'chats',
      'calls',
      'updates',
      'communities',
      'status',
      'spotlight',
      'stories',
      'tap to chat',
      'tap to view',
      'tap to load',
      'new snap',
      'unviewed story',
      'view story',
      'add friend',
      'create group',
      'online',
      'typing...',
      'tap for more info',
      'info',
      'turn on notifications',
      'never miss snaps',
      'add friends',
      'find friends',
    };
    if (uiNavigationGarbage.contains(lower)) return true;
    if (lower.contains('turn on notifications') || lower.contains('never miss snaps')) return true;

    // Snapchat streaks / feed chips (e.g., "Delivered 1h 298🔥", "Opened 2m", "Sent 5h")
    if (RegExp(r'^(delivered|opened|received|sent)\s+\d+.*', caseSensitive: false).hasMatch(t)) {
      return true;
    }
    if (RegExp(r'^\d+🔥$').hasMatch(t)) return true;

    // Instagram scraper noise: engagement metrics, feed artifacts, standalone handles
    // "Like number is2993. View likes", "Comment number is22. View comments"
    if (RegExp(r'^(like|comment|reshare|save|repost)\s+number\s+is\d+', caseSensitive: false).hasMatch(t)) return true;
    if (RegExp(r'^view\s+(likes|comments|all\s+comments)', caseSensitive: false).hasMatch(t)) return true;
    // "Reposted 66 times", "Reshare number is1402"
    if (RegExp(r'^reposted\s+\d+\s+times?', caseSensitive: false).hasMatch(t)) return true;
    // "Save number is103", "Saved to collection"
    if (RegExp(r'^save(d)?\s+(number|to\s)', caseSensitive: false).hasMatch(t)) return true;
    // "Sent 40m ago", "Seen 2h ago"
    if (RegExp(r'^(sent|seen|active)\s+\d+\s*(m|h|d|w)\s*(ago)?$', caseSensitive: false).hasMatch(t)) return true;
    // Standalone Instagram handles: "@username" only (no message text)
    if (RegExp(r'^@[a-zA-Z0-9_.]+$').hasMatch(t) && t.length < 30) return true;
    // Instagram navigation UI: "Liked by X and Y others", "Explore", "Reel", etc.
    const instaUiGarbage = {
      'liked by',
      'explore',
      'reels',
      'reel',
      'share',
      'comment',
      'like',
      'save',
      'follow',
      'following',
      'followers',
      'suggested for you',
      'sponsored',
      'see translation',
      'view all comments',
      'add a comment...',
      'more',
      'less',
    };
    if (instaUiGarbage.contains(lower)) return true;
    // "Liked by username and 234 others"
    if (RegExp(r'^liked by .+ and \d+ others?$', caseSensitive: false).hasMatch(t)) return true;

    return false;
  }

  static ParsedChatMessage parseMessageContent(
    String rawSender,
    String rawText,
    bool rawDeleted,
  ) {
    String text = rawText.trim();
    String sender = rawSender.trim();
    bool isDeleted = rawDeleted;

    // Detect WhatsApp/Telegram Deleted for Everyone
    final lowerText = text.toLowerCase();
    if (lowerText.contains('this message was deleted') ||
        lowerText.contains('you deleted this message') ||
        lowerText.contains('message deleted by sender')) {
      isDeleted = true;
      text = '🚫 This message was deleted by sender (Captured before deletion)';
    }

    // 1. WhatsApp group message prefix: "~ Sonia Arora: message text"
    final tildeMatch = RegExp(r'^~\s*([^:]+):\s*(.*)$', dotAll: true).firstMatch(text);
    if (tildeMatch != null) {
      final extractedSender = tildeMatch.group(1)?.trim() ?? '';
      final body = tildeMatch.group(2)?.trim() ?? '';
      if (extractedSender.isNotEmpty &&
          !extractedSender.toLowerCase().contains('team id') &&
          !extractedSender.toLowerCase().contains('team name')) {
        sender = extractedSender;
        text = body.isNotEmpty ? body : text;
      }
    }
    // Note: Arbitrary colons inside message text (e.g. "Team ID: 1234", "Note: please check")
    // must NEVER overwrite sender! Sender is strictly preserved from the thread contact.

    return ParsedChatMessage(
      sender: sender,
      cleanText: text,
      isDeleted: isDeleted,
    );
  }

  static String normalizeContactName(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.contains('harshit') || lower.contains('kamboj')) {
      return 'Harshit Kamboj';
    }
    return raw.trim();
  }

  static bool isWatchlistContact(String name) {
    final lower = name.toLowerCase().trim();
    return lower.contains('harshit') || lower.contains('kamboj');
  }

  static bool isAmbientVoiceRecord(String id, String contactName, String phoneNumber) {
    final lowerId = id.toLowerCase().trim();
    final lowerName = contactName.toLowerCase().trim();
    final lowerPhone = phoneNumber.toLowerCase().trim();
    return lowerId.startsWith('ambient_') ||
        lowerName.contains('ambient voice') ||
        lowerPhone.contains('pocket mic');
  }

  String? _resolveSenderFromNotifications(AppType app, DateTime dt, [String? text]) {
    final notifs = _childNotifications[_activeChildId] ?? [];
    if (notifs.isEmpty) return null;

    final targetAppStr = app.displayName.toLowerCase();
    final cleanMsg = text?.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') ?? '';

    for (final n in notifs) {
      if (n.appName.toLowerCase().contains(targetAppStr) || targetAppStr.contains(n.appName.toLowerCase())) {
        final diffSeconds = dt.difference(n.timestamp).inSeconds.abs();
        // Strict verification: Must be within 15 seconds AND text must correlate
        if (diffSeconds <= 15 && n.title.isNotEmpty && n.title != 'Unknown' && !n.title.contains('Contact')) {
          if (cleanMsg.isEmpty) {
            if (diffSeconds <= 5) return n.title;
          } else {
            final cleanNotif = n.message.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
            if (cleanNotif.contains(cleanMsg) || cleanMsg.contains(cleanNotif)) {
              return n.title;
            }
          }
        }
      }
    }
    return null;
  }

  void _mergeNotificationsIntoActiveChats() {
    final notifs = _childNotifications[_activeChildId] ?? [];
    final existingMsgs = _childChatMessages[_activeChildId] ?? [];

    // Blacklist of fake/system non-contact names that must never be treated as people
    final fakeContactKeywords = {
      'whatsapp contact',
      'instagram contact',
      'snapchat chat',
      'snapchat contact',
      'telegram contact',
      'social contact',
      'unknown',
      'messages',
      'all messages',
      'team id',
      'team name',
      'turn on notifications',
      'never miss snaps',
      'add friends',
      'find friends',
      'sent 1-view snap',
      'incoming snap',
      'aryan (child) [sent 1-view snap]',
    };

    final staticRegex = RegExp(r'[^a-z0-9]');
    String cleanTextNorm(String s) =>
        s.toLowerCase().replaceAll(staticRegex, '').trim();

    // Pre-compute normalized notifications once
    final notifData = notifs.map((n) {
      return (
        notif: n,
        norm: cleanTextNorm(n.message),
        appNameLower: n.appName.toLowerCase(),
      );
    }).toList();

    // 1. Cross-verify existing scraped messages against real notifications
    for (int i = 0; i < existingMsgs.length; i++) {
      final msg = existingMsgs[i];
      final msgNorm = cleanTextNorm(msg.messageText);
      if (msgNorm.isEmpty) continue;

      // Find matching notification in same app within 120 seconds
      NotificationItem? matchedNotif;
      final msgAppLower = msg.appType.displayName.toLowerCase();

      for (final nd in notifData) {
        final timeDiff = msg.timestamp.difference(nd.notif.timestamp).inSeconds.abs();
        if (timeDiff > 120) continue;

        final sameApp = nd.appNameLower.contains(msgAppLower) ||
            msgAppLower.contains(nd.appNameLower);
        if (!sameApp) continue;

        final notifNorm = nd.norm;
        if (notifNorm.isEmpty) continue;

        final textMatches = msgNorm == notifNorm ||
            (msgNorm.length > 5 && notifNorm.contains(msgNorm)) ||
            (notifNorm.length > 5 && msgNorm.contains(notifNorm));

        if (textMatches) {
          matchedNotif = nd.notif;
          break;
        }
      }

      if (matchedNotif != null) {
        // Dual-verified! Notification provides clean 100% verified sender name from OS
        final verifiedSender = matchedNotif.title.trim().isNotEmpty && matchedNotif.title != 'Unknown'
            ? matchedNotif.title.trim()
            : msg.contactName;

        existingMsgs[i] = ChatMessage(
          id: msg.id,
          appType: msg.appType,
          contactName: verifiedSender,
          contactIdentifier: verifiedSender,
          messageText: msg.messageText,
          timestamp: msg.timestamp,
          isIncoming: msg.isIncoming,
          isDeletedBackup: msg.isDeletedBackup || matchedNotif.isDeletedBackup,
          isWatchlistTarget: msg.isWatchlistTarget || matchedNotif.isSensitiveAlert,
          voiceNoteUrl: msg.voiceNoteUrl,
          voiceNoteDurationSeconds: msg.voiceNoteDurationSeconds,
          mediaUrl: msg.mediaUrl,
          mediaType: msg.mediaType,
          isViewOnce: msg.isViewOnce,
          isDualVerified: true, // Marked as dual-verified!
        );
      } else {
        // If message has a generic or fake contact name, resolve from nearby notifications in that app with text correlation
        final lowerContact = msg.contactName.toLowerCase().trim();
        final isGeneric = fakeContactKeywords.any((k) => lowerContact.contains(k));
        if (isGeneric) {
          final resolved = _resolveSenderFromNotifications(msg.appType, msg.timestamp, msg.messageText);
          if (resolved != null && resolved.isNotEmpty) {
            existingMsgs[i] = ChatMessage(
              id: msg.id,
              appType: msg.appType,
              contactName: resolved,
              contactIdentifier: resolved,
              messageText: msg.messageText,
              timestamp: msg.timestamp,
              isIncoming: msg.isIncoming,
              isDeletedBackup: msg.isDeletedBackup,
              isWatchlistTarget: msg.isWatchlistTarget,
              voiceNoteUrl: msg.voiceNoteUrl,
              voiceNoteDurationSeconds: msg.voiceNoteDurationSeconds,
              mediaUrl: msg.mediaUrl,
              mediaType: msg.mediaType,
              isViewOnce: msg.isViewOnce,
              isDualVerified: false,
            );
          }
        }
      }
    }

    // Pre-cache normalized texts for existingMsgs to make step 2 instant
    final existingNorms = existingMsgs.map((m) => (msg: m, norm: cleanTextNorm(m.messageText))).toList();

    // 2. Add notifications that were missed by the screen scraper (e.g. received when screen was off or deleted)
    for (final nd in notifData) {
      final notif = nd.notif;
      final appNameLower = nd.appNameLower;
      AppType app = AppType.whatsApp;
      if (appNameLower.contains('insta')) app = AppType.instagram;
      if (appNameLower.contains('tele')) app = AppType.telegram;
      if (appNameLower.contains('snap')) app = AppType.snapchat;
      if (appNameLower.contains('sms')) app = AppType.sms;

      final isSocial = appNameLower.contains('what') ||
          appNameLower.contains('insta') ||
          appNameLower.contains('tele') ||
          appNameLower.contains('snap') ||
          appNameLower.contains('sms') ||
          notif.packageName.contains('mms');

      if (!isSocial || notif.message.trim().isEmpty) continue;
      if (isScraperGarbage(notif.message)) continue;

      final notifNorm = nd.norm;
      if (notifNorm.isEmpty) continue;

      // Check if already in existingMsgs
      final alreadyPresent = existingNorms.any((entry) {
        final m = entry.msg;
        final timeDiff = (m.timestamp.difference(notif.timestamp)).inSeconds.abs();
        if (timeDiff > 120 && !(m.contactName == notif.title && timeDiff < 8)) return false;

        final sameApp = m.appType == app;
        if (!sameApp) return false;

        final mNorm = entry.norm;
        final textMatches = mNorm == notifNorm ||
            (mNorm.length > 5 && notifNorm.contains(mNorm)) ||
            (notifNorm.length > 5 && mNorm.contains(notifNorm));
        return textMatches || (m.contactName == notif.title && timeDiff < 8);
      });

      if (!alreadyPresent) {
        final newMsg = ChatMessage(
          id: 'notif_mirror_${notif.id}',
          appType: app,
          contactName: notif.title.isNotEmpty ? notif.title : 'Unknown',
          contactIdentifier: notif.title,
          messageText: notif.message,
          timestamp: notif.timestamp,
          isIncoming: true,
          isDeletedBackup: notif.isDeletedBackup,
          isWatchlistTarget: notif.isSensitiveAlert,
          isDualVerified: false,
        );
        existingMsgs.add(newMsg);
        existingNorms.add((msg: newMsg, norm: notifNorm));
      }
    }

    // Sort descending by timestamp
    existingMsgs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<CallRecord> getCallRecordsForContact(String contactName, String contactIdentifier) {
    final cleanName = contactName.toLowerCase().trim();
    final simplifiedName = cleanName.replaceAll(RegExp(r'\[.*?\]'), '').trim();
    final digits = contactIdentifier.replaceAll(RegExp(r'\D'), '');

    final allCalls = callRecords;
    return allCalls.where((call) {
      final callName = call.contactName.toLowerCase().trim();
      final callDigits = call.phoneNumber.replaceAll(RegExp(r'\D'), '');

      if (digits.length >= 7 && callDigits.isNotEmpty && (digits.contains(callDigits) || callDigits.contains(digits))) {
        return true;
      }
      if (simplifiedName.length > 2 && callName.isNotEmpty) {
        if (callName.contains(simplifiedName) || simplifiedName.contains(callName)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  void _dispatchRemoteCommand(String action, [Map<String, dynamic>? payload]) {
    try {
      final targetCode = activePairingCode.isNotEmpty ? activePairingCode : _activeChildId;
      _supabaseSync.sendCommand(targetCode, action, payload);
    } catch (e) {
      debugPrint("Could not dispatch command to Supabase: $e");
    }
  }

  void sendVoiceIntercom(String announcement) {
    debugPrint("Broadcasting voice intercom to ${activeChild.name}: $announcement");
    _dispatchRemoteCommand('LOUDSPEAKER_INTERCOM', {'announcement': announcement});
  }

  DeviceStatus get deviceStatus {
    final c = activeChild;
    return DeviceStatus(
      deviceName: "${c.name}'s Phone",
      model: c.deviceModel,
      batteryLevel: c.batteryLevel,
      isCharging: false,
      isOnline: c.isOnline,
      lastSeen: DateTime.now(),
      locationAddress: c.locationAddress,
      latitude: 28.6139,
      longitude: 77.2090,
    );
  }

  bool _isPhoneLocked = false;
  bool get isPhoneLocked => _isPhoneLocked;

  bool _isLiveScreenActive = false;
  bool get isLiveScreenActive => _isLiveScreenActive;

  bool _isRemoteCameraActive = false;
  bool get isRemoteCameraActive => _isRemoteCameraActive;

  bool _isFlashlightOn = false;
  bool get isFlashlightOn => _isFlashlightOn;

  bool _isStealthScreenGuardEnabled = true; // Auto-cut camera/mic when child turns on screen
  bool get isStealthScreenGuardEnabled => _isStealthScreenGuardEnabled;

  void toggleStealthScreenGuard() {
    _isStealthScreenGuardEnabled = !_isStealthScreenGuardEnabled;
    _dispatchRemoteCommand('SET_STEALTH_GUARD', {'enabled': _isStealthScreenGuardEnabled});
    notifyListeners();
  }

  void triggerAmbientAudioRecording() {
    _dispatchRemoteCommand('START_AMBIENT_RECORDING', {});
    debugPrint("Dispatched START_AMBIENT_RECORDING to child device");
  }

  void stopAmbientAudioRecording() {
    _dispatchRemoteCommand('STOP_AMBIENT_RECORDING', {});
    debugPrint("Dispatched STOP_AMBIENT_RECORDING to child device");
  }

  bool _isGeofenceEnabled = false; // Default OFF so child is never locked or restricted unexpectedly
  bool get isGeofenceEnabled => _isGeofenceEnabled;

  void toggleGeofence() {
    _isGeofenceEnabled = !_isGeofenceEnabled;
    _dispatchRemoteCommand('SET_GEOFENCE_ACTIVE', {'enabled': _isGeofenceEnabled});
    notifyListeners();
  }

  void switchDisguise(String disguiseName) {
    final idx = _children.indexWhere((c) => c.id == _activeChildId);
    if (idx != -1) {
      _children[idx] = _children[idx].copyWith(selectedDisguise: disguiseName);
      _saveLocalPersistence();
      notifyListeners();
    }
    _dispatchRemoteCommand('SWITCH_DISGUISE', {'disguise': disguiseName});
    debugPrint("Dispatched SWITCH_DISGUISE ($disguiseName) to child device");
  }

  String _currentCameraLens = "back"; // "back" or "front"
  String get currentCameraLens => _currentCameraLens;

  String? _currentlyPlayingAudioId;
  String? get currentlyPlayingAudioId => _currentlyPlayingAudioId;

  // Selected App tab in Chats screen
  AppType _selectedChatApp = AppType.whatsApp;
  AppType get selectedChatApp => _selectedChatApp;

  // Call Records per Child — populated from Supabase & LAN Sync
  final Map<String, List<CallRecord>> _childCallRecords = {};
  List<CallRecord> get callRecords => _childCallRecords[_activeChildId] ?? [];

  // Ambient Soundbites & Voice Activity Logs per Child — populated from Supabase & LAN Sync
  final Map<String, List<AmbientLogItem>> _childAmbientLogs = {};
  List<AmbientLogItem> get ambientLogs => _childAmbientLogs[_activeChildId] ?? [];

  bool _autoPurgeCloudStorage = true;
  bool get autoPurgeCloudStorage => _autoPurgeCloudStorage;

  void toggleAutoPurgeCloudStorage() {
    _autoPurgeCloudStorage = !_autoPurgeCloudStorage;
    notifyListeners();
  }

  void purgeCloudAudio(String logId) {
    final list = _childAmbientLogs[_activeChildId];
    if (list != null) {
      final idx = list.indexWhere((l) => l.id == logId);
      if (idx != -1) {
        list[idx] = list[idx].copyWith(
          isPurgedFromCloud: true,
        );
        notifyListeners();
      }
    }
  }

  double get totalCloudPurgedMb {
    final list = _childAmbientLogs[_activeChildId] ?? [];
    final totalKb = list
        .where((l) => l.isPurgedFromCloud)
        .fold<int>(0, (total, item) => total + item.storageFreedKb);
    return totalKb / 1024.0;
  }

  // Chat Messages Date Range Filter (Default: All Time)
  ChatDateRange _selectedChatRange = ChatDateRange.allTime;
  ChatDateRange get selectedChatRange => _selectedChatRange;

  void setSelectedChatRange(ChatDateRange range) {
    _selectedChatRange = range;
    notifyListeners();
  }

  Future<void> fetchHistoricalChatsFromDevice(int daysBack) async {
    _dispatchRemoteCommand('FETCH_HISTORICAL_CHATS', {'daysBack': daysBack});
    debugPrint("Dispatched FETCH_HISTORICAL_CHATS ($daysBack days) to child device");
    await syncFromSupabase(chatLimit: 10000);
  }


  // Master Archive of Chat Messages per Child — populated from Supabase & LAN Sync
  final Map<String, List<ChatMessage>> _childChatMessages = {};

  List<ChatMessage> get chatMessages {
    final msgs = _childChatMessages[_activeChildId] ?? [];
    final now = DateTime.now();
    switch (_selectedChatRange) {
      case ChatDateRange.last2Days:
        final cutoff = now.subtract(const Duration(days: 2));
        return msgs.where((m) => m.timestamp.isAfter(cutoff)).toList();
      case ChatDateRange.last7Days:
        final cutoff = now.subtract(const Duration(days: 7));
        return msgs.where((m) => m.timestamp.isAfter(cutoff)).toList();
      case ChatDateRange.last30Days:
        final cutoff = now.subtract(const Duration(days: 30));
        return msgs.where((m) => m.timestamp.isAfter(cutoff)).toList();
      case ChatDateRange.allTime:
        return msgs;
    }
  }

  List<ChatMessage> get allArchivedChatMessages => _childChatMessages[_activeChildId] ?? [];

  // Notification Items per Child — populated from Supabase & LAN Sync
  final Map<String, List<NotificationItem>> _childNotifications = {};
  List<NotificationItem> get notifications => _childNotifications[_activeChildId] ?? [];

  // Watchlist Targets per Child — Harshit Kamboj pre-seeded for default monitored child
  final Map<String, List<WatchlistTarget>> _childWatchlists = {
    _defaultChildCode: [
      WatchlistTarget(
        id: 'watchlist_harshit_kamboj',
        name: 'Harshit Kamboj',
        identifier: '@harshit_kamboj97',
        note: 'High Watchlist Priority across Snapchat, Instagram & WhatsApp',
        isHighPriority: true,
        totalCalls: 0,
        totalChats: 0,
        lastInteracted: DateTime(2026, 10, 4),
      ),
    ],
  };

  List<WatchlistTarget> get watchlistTargets {
    final rawTargets = _childWatchlists[_activeChildId] ?? [];
    final calls = _childCallRecords[_activeChildId] ?? [];
    final chats = _childChatMessages[_activeChildId] ?? [];

    return rawTargets.map((t) {
      final targetNameLower = t.name.toLowerCase().trim();
      final targetIdLower = t.identifier.toLowerCase().replaceAll('@', '').trim();

      final matchedCalls = calls.where((c) {
        final cName = c.contactName.toLowerCase();
        final cPhone = c.phoneNumber.toLowerCase();
        return (targetNameLower.isNotEmpty && cName.contains(targetNameLower)) ||
            (targetIdLower.isNotEmpty && (cName.contains(targetIdLower) || cPhone.contains(targetIdLower)));
      }).toList();

      final matchedChats = chats.where((m) {
        final mName = m.contactName.toLowerCase();
        final mId = m.contactIdentifier.toLowerCase();
        return (targetNameLower.isNotEmpty && (mName.contains(targetNameLower) || mId.contains(targetNameLower))) ||
            (targetIdLower.isNotEmpty && (mName.contains(targetIdLower) || mId.contains(targetIdLower)));
      }).toList();

      DateTime lastTime = t.lastInteracted;
      if (matchedCalls.isNotEmpty && matchedCalls.first.timestamp.isAfter(lastTime)) {
        lastTime = matchedCalls.first.timestamp;
      }
      if (matchedChats.isNotEmpty && matchedChats.first.timestamp.isAfter(lastTime)) {
        lastTime = matchedChats.first.timestamp;
      }

      return WatchlistTarget(
        id: t.id,
        name: t.name,
        identifier: t.identifier,
        note: t.note,
        isHighPriority: t.isHighPriority,
        totalCalls: matchedCalls.isNotEmpty ? matchedCalls.length : t.totalCalls,
        totalChats: matchedChats.isNotEmpty ? matchedChats.length : t.totalChats,
        lastInteracted: lastTime,
      );
    }).toList();
  }

  void setSelectedChatApp(AppType app) {
    _selectedChatApp = app;
    notifyListeners();
  }

  void toggleLockPhone() {
    _isPhoneLocked = !_isPhoneLocked;
    if (_isPhoneLocked) {
      _dispatchRemoteCommand('LOCK_PHONE', {});
    }
    notifyListeners();
  }

  void toggleLiveScreen() {
    _isLiveScreenActive = !_isLiveScreenActive;
    if (_isLiveScreenActive) _isRemoteCameraActive = false;
    notifyListeners();
  }

  void toggleRemoteCamera() {
    _isRemoteCameraActive = !_isRemoteCameraActive;
    if (_isRemoteCameraActive) _isLiveScreenActive = false;
    _dispatchRemoteCommand(_isRemoteCameraActive ? 'START_CAMERA_STREAM' : 'STOP_CAMERA_STREAM', {'lens': _currentCameraLens});
    debugPrint("Dispatched ${_isRemoteCameraActive ? 'START_CAMERA_STREAM' : 'STOP_CAMERA_STREAM'} to child");
    notifyListeners();
  }

  void switchCameraLens() {
    _currentCameraLens = (_currentCameraLens == "back") ? "front" : "back";
    if (_isRemoteCameraActive) {
      _dispatchRemoteCommand('SWITCH_CAMERA_LENS', {'lens': _currentCameraLens});
    }
    notifyListeners();
  }

  void toggleFlashlight() {
    _isFlashlightOn = !_isFlashlightOn;
    notifyListeners();
  }

  Future<void> togglePlayAudio(String callId) async {
    final allCalls = callRecords;
    CallRecord? targetCall;
    for (final c in allCalls) {
      if (c.id == callId) {
        targetCall = c;
        break;
      }
    }

    if (AudioPlaybackService.instance.isPlaying && AudioPlaybackService.instance.currentMediaId == callId) {
      await AudioPlaybackService.instance.pause();
      _currentlyPlayingAudioId = null;
    } else {
      _currentlyPlayingAudioId = callId;
      if (targetCall != null && targetCall.recordingUrl != null && targetCall.recordingUrl!.isNotEmpty) {
        await AudioPlaybackService.instance.play(
          mediaId: callId,
          url: targetCall.recordingUrl,
        );
      }
    }
    notifyListeners();
  }

  Future<void> togglePlayAudioUrl(String mediaId, String url) async {
    if (AudioPlaybackService.instance.isPlaying && AudioPlaybackService.instance.currentMediaId == mediaId) {
      await AudioPlaybackService.instance.pause();
      _currentlyPlayingAudioId = null;
    } else {
      _currentlyPlayingAudioId = mediaId;
      await AudioPlaybackService.instance.play(
        mediaId: mediaId,
        url: url,
      );
    }
    notifyListeners();
  }

  void addWatchlistTarget(String name, String identifier, String note) {
    _childWatchlists.putIfAbsent(_activeChildId, () => []).add(
      WatchlistTarget(
        id: "target_${DateTime.now().millisecondsSinceEpoch}",
        name: name,
        identifier: identifier,
        note: note,
        isHighPriority: true,
        totalCalls: 0,
        totalChats: 0,
        lastInteracted: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _lanLiveStreamSub?.cancel();
    _lanDiscoveryTimer?.cancel();
    _supabaseSyncTimer?.cancel();
    super.dispose();
  }
}
