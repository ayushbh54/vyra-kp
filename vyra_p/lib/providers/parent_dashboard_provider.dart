import 'package:flutter/foundation.dart';
import '../models/device_status.dart';
import '../models/child_profile.dart';
import '../models/call_record.dart';
import '../models/chat_message.dart';
import '../models/notification_item.dart';
import '../models/watchlist_target.dart';

class ParentDashboardProvider extends ChangeNotifier {
  final List<ChildProfile> _children = const [
    ChildProfile(
      id: "child_1",
      name: "Aryan",
      deviceModel: "Vivo T3 Pro 5G",
      batteryLevel: 84,
      isOnline: true,
      locationAddress: "Near City Coaching Center, Sector 4",
      selectedDisguise: "SIM Toolkit",
    ),
    ChildProfile(
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
    notifyListeners();
  }

  void sendVoiceIntercom(String announcement) {
    // In production, sends audio buffer/command via WebSockets or Firebase Realtime
    debugPrint("Broadcasting voice intercom to ${activeChild.name}: $announcement");
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
}
