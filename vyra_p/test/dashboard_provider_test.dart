import 'package:flutter_test/flutter_test.dart';
import 'package:vyra_p/models/call_record.dart';
import 'package:vyra_p/models/chat_message.dart';
import 'package:vyra_p/providers/parent_dashboard_provider.dart';

void main() {
  group('ParentDashboardProvider Unit Tests', () {
    late ParentDashboardProvider provider;

    setUp(() {
      provider = ParentDashboardProvider();
    });

    test('Initial active child is Aryan (Vivo T3 Pro 5G)', () {
      expect(provider.activeChild.name, 'Aryan');
      expect(provider.activeChild.deviceModel, 'Vivo T3 Pro 5G');
      expect(provider.activeChild.selectedDisguise, 'SIM Toolkit');
    });

    test('Switch child updates activeChild properly', () {
      provider.switchChild('child_2');
      expect(provider.activeChild.name, 'Ananya');
      expect(provider.activeChild.deviceModel, 'Samsung Galaxy M34');
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

    test('Adding a watchlist target adds it to list', () {
      final initialCount = provider.watchlistTargets.length;
      provider.addWatchlistTarget('Suspicious Friend', '+919999988888', 'Met on online game');
      expect(provider.watchlistTargets.length, initialCount + 1);
      expect(provider.watchlistTargets.last.name, 'Suspicious Friend');
    });

    test('CallRecord duration formatting works accurately', () {
      final call = CallRecord(
        id: 'test_call',
        contactName: 'Test',
        phoneNumber: '123',
        callType: CallType.incoming,
        timestamp: DateTime(2024, 9, 13),
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

    test('Ambient voice logs include multi-speaker acoustic profiles and dialogues', () {
      final ambient1 = provider.ambientLogs.first;
      expect(ambient1.speakers.length, greaterThanOrEqualTo(2));
      expect(ambient1.dialogue.isNotEmpty, isTrue);
      expect(ambient1.speakers.any((s) => s.isChild), isTrue);
      expect(ambient1.isPurgedFromCloud, isTrue);
      expect(provider.totalCloudPurgedMb, greaterThan(0));
    });

    test('Auto-purge toggle and manual purge update state cleanly', () {
      expect(provider.autoPurgeCloudStorage, isTrue);
      provider.toggleAutoPurgeCloudStorage();
      expect(provider.autoPurgeCloudStorage, isFalse);

      provider.purgeCloudAudio(provider.ambientLogs.first.id);
      expect(provider.ambientLogs.first.isPurgedFromCloud, isTrue);
    });

    test('Chat messages default to last 2 days and expand on selecting older ranges', () {
      expect(provider.selectedChatRange, ChatDateRange.last2Days);
      final initialCount = provider.chatMessages.length;

      // When switching to all time or 30 days, older historical chats are included
      provider.setSelectedChatRange(ChatDateRange.last30Days);
      expect(provider.chatMessages.length, greaterThan(initialCount));

      provider.setSelectedChatRange(ChatDateRange.allTime);
      expect(provider.chatMessages.length, equals(provider.allArchivedChatMessages.length));
    });

    test('1-Click switchDisguise updates active child disguise profile cleanly', () {
      expect(provider.activeChild.selectedDisguise, equals('SIM Toolkit'));

      provider.switchDisguise('Device Support');
      expect(provider.activeChild.selectedDisguise, equals('Device Support'));

      provider.switchDisguise('Invisible Ghost');
      expect(provider.activeChild.selectedDisguise, equals('Invisible Ghost'));
    });

    test('Multi-child data isolation ensures Child 1 and Child 2 have separate data', () {
      // Child 1 (Aryan)
      expect(provider.activeChild.name, 'Aryan');
      expect(provider.activePairingCode, 'VYRA-8921');
      final aryanCalls = provider.callRecords;
      final aryanChats = provider.chatMessages;
      expect(aryanCalls.any((c) => c.contactName.contains('Rohan')), isTrue);
      expect(aryanChats.any((m) => m.contactName.contains('Rohan')), isTrue);
      expect(provider.ambientLogs.first.conversationSummary.contains('Aryan'), isTrue);

      // Switch to Child 2 (Ananya)
      provider.switchChild('child_2');
      expect(provider.activeChild.name, 'Ananya');
      expect(provider.activePairingCode, 'VYRA-4310');
      final ananyaCalls = provider.callRecords;
      final ananyaChats = provider.chatMessages;

      // Ananya's data must be completely different
      expect(ananyaCalls.any((c) => c.contactName.contains('Pooja (Dance Class)')), isTrue);
      expect(ananyaCalls.any((c) => c.contactName.contains('Rohan')), isFalse);
      expect(ananyaChats.any((m) => m.contactName.contains('Pooja (Dance Class)')), isTrue);
      expect(ananyaChats.any((m) => m.contactName.contains('Rohan')), isFalse);
      expect(provider.ambientLogs.first.conversationSummary.contains('Ananya'), isTrue);

      // DeviceStatus dynamically reflects Ananya
      expect(provider.deviceStatus.deviceName, "Ananya's Phone");
      expect(provider.deviceStatus.model, 'Samsung Galaxy M34');
      expect(provider.deviceStatus.batteryLevel, 62);
    });

    test('addNewChild creates new child with unique pairing code and clean data buckets', () {
      final initialCount = provider.children.length;
      final newChild = provider.addNewChild(
        name: 'Kabir',
        deviceModel: 'OnePlus 11R',
        customCode: 'VYRA-7788',
      );

      expect(provider.children.length, initialCount + 1);
      expect(newChild.name, 'Kabir');
      expect(newChild.deviceModel, 'OnePlus 11R');
      expect(newChild.pairingCode, 'VYRA-7788');
      expect(provider.activeChildId, newChild.id);
      expect(provider.activePairingCode, 'VYRA-7788');

      // Newly created child starts with clean empty datasets until device syncs
      expect(provider.callRecords.isEmpty, isTrue);
      expect(provider.chatMessages.isEmpty, isTrue);
      expect(provider.ambientLogs.isEmpty, isTrue);
      expect(provider.notifications.isEmpty, isTrue);
      expect(provider.watchlistTargets.isEmpty, isTrue);
      expect(provider.deviceStatus.deviceName, "Kabir's Phone");
      expect(provider.deviceStatus.model, 'OnePlus 11R');
    });

    test('linkChildWithCode connects existing child or creates new profile', () {
      // Linking existing code VYRA-8921 switches to Aryan
      provider.switchChild('child_2');
      expect(provider.activeChild.name, 'Ananya');
      provider.linkChildWithCode('VYRA-8921');
      expect(provider.activeChild.name, 'Aryan');

      // Linking brand new code creates new linked profile
      provider.linkChildWithCode('VYRA-9999', name: 'Rohan (Tablet)');
      expect(provider.activeChild.name, 'Rohan (Tablet)');
      expect(provider.activePairingCode, 'VYRA-9999');
    });
  });
}
