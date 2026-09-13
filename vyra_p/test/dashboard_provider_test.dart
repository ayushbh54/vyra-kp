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
  });
}
