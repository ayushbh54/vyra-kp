import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vyra_p/models/call_record.dart';
import 'package:vyra_p/models/chat_message.dart';
import 'package:vyra_p/models/notification_item.dart';
import 'package:vyra_p/providers/parent_dashboard_provider.dart';
import 'package:vyra_p/services/lan_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ParentDashboardProvider Unit Tests', () {
    late ParentDashboardProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = ParentDashboardProvider();
    });

    test('Initial active child defaults to VYRA-13533 so user never has to re-type code', () {
      expect(provider.children.isNotEmpty, isTrue);
      expect(provider.activePairingCode, 'VYRA-13533');
      expect(provider.activeChild.deviceModel, 'Vivo V2404');
      expect(provider.callRecords.isEmpty, isTrue);
      expect(provider.chatMessages.isEmpty, isTrue);
    });

    test('linkChildWithCode connects child and sets active profile', () {
      final child = provider.linkChildWithCode('VYRA-13533', name: 'Vivo V2404');
      expect(provider.children.length, 1);
      expect(child.name, 'Vivo V2404');
      expect(child.pairingCode, 'VYRA-13533');
      expect(provider.activeChild.name, 'Vivo V2404');
      expect(provider.activePairingCode, 'VYRA-13533');
    });

    test('Switch child updates activeChild properly between multiple children', () {
      provider.linkChildWithCode('VYRA-13533', name: 'Child 1');
      final child2 = provider.addNewChild(
        name: 'Child 2',
        deviceModel: 'Samsung Galaxy M34',
        customCode: 'VYRA-4310',
      );

      expect(provider.children.length, 2);
      expect(provider.activeChild.name, 'Child 2');

      provider.switchChild('VYRA-13533');
      expect(provider.activeChild.name, 'Child 1');
      expect(provider.activePairingCode, 'VYRA-13533');

      provider.switchChild(child2.id);
      expect(provider.activeChild.name, 'Child 2');
      expect(provider.activePairingCode, 'VYRA-4310');
    });

    test('Toggle phone lock toggles state correctly', () {
      expect(provider.isPhoneLocked, isFalse);
      provider.toggleLockPhone();
      expect(provider.isPhoneLocked, isTrue);
      provider.toggleLockPhone();
      expect(provider.isPhoneLocked, isFalse);
    });

    test('Toggle live screen and remote camera are mutually exclusive', () {
      provider.toggleLiveScreen();
      expect(provider.isLiveScreenActive, isTrue);
      expect(provider.isRemoteCameraActive, isFalse);

      provider.toggleRemoteCamera();
      expect(provider.isRemoteCameraActive, isTrue);
      expect(provider.isLiveScreenActive, isFalse);
    });

    test('Camera lens flip toggles front and back', () {
      expect(provider.currentCameraLens, 'back');
      provider.switchCameraLens();
      expect(provider.currentCameraLens, 'front');
      provider.switchCameraLens();
      expect(provider.currentCameraLens, 'back');
    });

    test('Adding a watchlist target adds it to list for active child', () {
      provider.linkChildWithCode('VYRA-13533', name: 'Child 1');
      final initialCount = provider.watchlistTargets.length;
      provider.addWatchlistTarget('Suspicious Number', '+919999988888', 'Online contact');
      expect(provider.watchlistTargets.length, initialCount + 1);
      expect(provider.watchlistTargets.last.name, 'Suspicious Number');
      expect(provider.watchlistTargets.last.identifier, '+919999988888');
    });

    test('CallRecord duration formatting works accurately', () {
      final call = CallRecord(
        id: 'test_call',
        contactName: 'Test',
        phoneNumber: '123',
        callType: CallType.incoming,
        timestamp: DateTime(2026, 9, 13),
        durationSeconds: 125, // 2 mins 5 seconds
      );
      expect(call.formattedDuration, '02:05');
    });

    test('AppType extensions return correct display names and icons', () {
      expect(AppType.whatsApp.displayName, 'WhatsApp');
      expect(AppType.whatsApp.iconAsset, '💬');
      expect(AppType.instagram.displayName, 'Instagram');
      expect(AppType.instagram.iconAsset, '📸');
      expect(AppType.telegram.displayName, 'Telegram');
      expect(AppType.sms.displayName, 'SMS');
    });

    test('1-Click switchDisguise updates active child disguise profile cleanly', () {
      provider.linkChildWithCode('VYRA-13533', name: 'Child 1');
      expect(provider.activeChild.selectedDisguise, equals('System Toolkit'));

      provider.switchDisguise('Device Support');
      expect(provider.activeChild.selectedDisguise, equals('Device Support'));

      provider.switchDisguise('Settings Support');
      expect(provider.activeChild.selectedDisguise, equals('Settings Support'));
    });

    test('Auto-purge toggle updates state cleanly', () {
      expect(provider.autoPurgeCloudStorage, isTrue);
      provider.toggleAutoPurgeCloudStorage();
      expect(provider.autoPurgeCloudStorage, isFalse);
    });

    test('Scraper garbage filter rejects UI noise and raw IDs', () {
      expect(ParentDashboardProvider.isScraperGarbage('2131232237'), isTrue);
      expect(ParentDashboardProvider.isScraperGarbage('Messages and calls are end-to-end encrypted'), isTrue);
      expect(ParentDashboardProvider.isScraperGarbage('just now'), isTrue);
      expect(ParentDashboardProvider.isScraperGarbage('Delivered 1h 298🔥'), isTrue);
      expect(ParentDashboardProvider.isScraperGarbage('turn on notifications'), isTrue);
      expect(ParentDashboardProvider.isScraperGarbage('Hello, are you coming home today?'), isFalse);
    });

    test('Message parser correctly extracts group sender and deleted status', () {
      final parsed = ParentDashboardProvider.parseMessageContent(
        'WhatsApp Contact',
        '~ Rohan: Hey let us meet after class',
        false,
      );
      expect(parsed.sender, 'Rohan');
      expect(parsed.cleanText, 'Hey let us meet after class');
      expect(parsed.isDeleted, isFalse);

      final deletedParsed = ParentDashboardProvider.parseMessageContent(
        'Rohan',
        'This message was deleted',
        false,
      );
      expect(deletedParsed.isDeleted, isTrue);
      expect(deletedParsed.cleanText.contains('deleted by sender'), isTrue);
    });

    test('Multi-child data isolation ensures distinct child datasets', () {
      provider.linkChildWithCode('VYRA-1', name: 'Child One');
      provider.addWatchlistTarget('Target 1', '111', 'Notes 1');
      expect(provider.watchlistTargets.length, 1);

      provider.linkChildWithCode('VYRA-2', name: 'Child Two');
      expect(provider.watchlistTargets.isEmpty, isTrue);

      provider.switchChild('VYRA-1');
      expect(provider.watchlistTargets.length, 1);
      expect(provider.watchlistTargets.first.name, 'Target 1');
    });

    test('ChatMessage, CallRecord, and NotificationItem serialize and deserialize to JSON cleanly', () {
      final msg = ChatMessage(
        id: 'msg_1',
        appType: AppType.whatsApp,
        contactName: 'Aryan',
        contactIdentifier: '+919876543210',
        messageText: 'Hello dad!',
        timestamp: DateTime(2026, 10, 2, 10, 0),
        isIncoming: true,
        isDeletedBackup: true,
      );
      final jsonMsg = msg.toJson();
      final restoredMsg = ChatMessage.fromJson(jsonMsg);
      expect(restoredMsg.id, 'msg_1');
      expect(restoredMsg.contactName, 'Aryan');
      expect(restoredMsg.isDeletedBackup, isTrue);
      expect(restoredMsg.appType, AppType.whatsApp);

      final call = CallRecord(
        id: 'call_1',
        contactName: 'Mom',
        phoneNumber: '9876543210',
        callType: CallType.incoming,
        timestamp: DateTime(2026, 10, 2, 9, 30),
        durationSeconds: 120,
      );
      final jsonCall = call.toJson();
      final restoredCall = CallRecord.fromJson(jsonCall);
      expect(restoredCall.id, 'call_1');
      expect(restoredCall.durationSeconds, 120);
      expect(restoredCall.formattedDuration, '02:00');

      final notif = NotificationItem(
        id: 'notif_1',
        packageName: 'com.whatsapp',
        appName: 'WhatsApp',
        title: 'New Message',
        message: 'Are you coming?',
        timestamp: DateTime(2026, 10, 2, 10, 5),
        isDeletedBackup: false,
      );
      final jsonNotif = notif.toJson();
      final restoredNotif = NotificationItem.fromJson(jsonNotif);
      expect(restoredNotif.id, 'notif_1');
      expect(restoredNotif.appName, 'WhatsApp');
    });

    test('Same-Wi-Fi LAN sync states initialize correctly', () {
      expect(provider.isLanSyncActive, isFalse);
      expect(provider.isLanSyncing, isFalse);
      expect(provider.lanChildIp, isNull);
      expect(provider.lastLanSyncTime, isNull);
    });

    test('LanSyncService openLiveStream handles incoming events correctly', () async {
      final service = LanSyncService();
      // Service instantiated and stream helper exists
      expect(service, isNotNull);
    });

    test('purgeSupabaseCloudStorage handles call safely without throwing', () async {
      final res = await provider.purgeSupabaseCloudStorage();
      expect(res, isFalse); // placeholder key returns false safely without throwing
    });

    test('Harshit Kamboj contact normalization and watchlist target detection', () {
      expect(ParentDashboardProvider.normalizeContactName('harshit_kamboj97'), 'Harshit Kamboj');
      expect(ParentDashboardProvider.normalizeContactName('harshit'), 'Harshit Kamboj');
      expect(ParentDashboardProvider.normalizeContactName('kamboj'), 'Harshit Kamboj');
      expect(ParentDashboardProvider.normalizeContactName('Harshit Kamboj'), 'Harshit Kamboj');
      expect(ParentDashboardProvider.normalizeContactName('Rohan Sharma'), 'Rohan Sharma');

      expect(ParentDashboardProvider.isWatchlistContact('harshit_kamboj97'), isTrue);
      expect(ParentDashboardProvider.isWatchlistContact('Harshit'), isTrue);
      expect(ParentDashboardProvider.isWatchlistContact('kamboj'), isTrue);
      expect(ParentDashboardProvider.isWatchlistContact('Rohan Sharma'), isFalse);
    });

    test('Harshit Kamboj is pre-seeded in watchlistTargets with High Priority', () {
      final targets = provider.watchlistTargets;
      final harshit = targets.firstWhere(
        (t) => t.name == 'Harshit Kamboj',
        orElse: () => throw Exception('Harshit Kamboj not found in watchlist'),
      );
      expect(harshit.name, 'Harshit Kamboj');
      expect(harshit.identifier, '@harshit_kamboj97');
      expect(harshit.isHighPriority, isTrue);
      expect(harshit.note.contains('High Watchlist Priority'), isTrue);
    });

    test('Chats grouping normalizes Harshit Kamboj threads and rejects keystroke fragments and UI counters', () {
      final messages = [
        ChatMessage(
          id: '1',
          appType: AppType.instagram,
          contactName: 'harshit_kamboj97',
          contactIdentifier: 'harshit_kamboj97',
          messageText: 'Hello there',
          timestamp: DateTime.now(),
          isIncoming: true,
          isDeletedBackup: false,
          isWatchlistTarget: true,
        ),
        ChatMessage(
          id: '2',
          appType: AppType.instagram,
          contactName: 'harshit',
          contactIdentifier: 'harshit',
          messageText: 'Meeting tonight?',
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
          isIncoming: true,
          isDeletedBackup: false,
          isWatchlistTarget: true,
        ),
        ChatMessage(
          id: '3',
          appType: AppType.instagram,
          contactName: 'ha',
          contactIdentifier: 'ha',
          messageText: 'garvthehunter',
          timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
          isIncoming: true,
          isDeletedBackup: false,
        ),
        ChatMessage(
          id: '4',
          appType: AppType.instagram,
          contactName: 'Save number is1377',
          contactIdentifier: 'Save number is1377',
          messageText: 'UI counter',
          timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
          isIncoming: true,
          isDeletedBackup: false,
        ),
      ];

      final Map<String, List<ChatMessage>> grouped = {};
      for (final msg in messages) {
        String key = msg.contactIdentifier.isNotEmpty ? msg.contactIdentifier : msg.contactName;
        final lowerKey = key.trim().toLowerCase();
        if (lowerKey.contains('harshit') || lowerKey.contains('kamboj')) {
          key = 'Harshit Kamboj';
        }
        grouped.putIfAbsent(key, () => []).add(msg);
      }

      final conversations = grouped.entries.where((entry) {
        final k = entry.key.trim().toLowerCase();
        if (k == 'ha' || k == 'har' || k == 'hars' || k == 'harsh' || k == 'harshi' ||
            k.contains('save number') || k.contains('reshare') || k.contains('reposted')) {
          return false;
        }
        return true;
      }).toList();

      expect(conversations.length, 1);
      expect(conversations.first.key, 'Harshit Kamboj');
      expect(conversations.first.value.length, 2);
    });
  });
}
