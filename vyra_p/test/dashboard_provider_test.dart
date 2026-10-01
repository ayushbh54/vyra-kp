import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vyra_p/models/call_record.dart';
import 'package:vyra_p/models/chat_message.dart';
import 'package:vyra_p/providers/parent_dashboard_provider.dart';

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
  });
}
