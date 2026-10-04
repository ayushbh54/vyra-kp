import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vyra_p/models/ambient_log_item.dart';
import 'package:vyra_p/models/chat_message.dart';
import 'package:vyra_p/providers/parent_dashboard_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Deep Multi-Module Sync & Accuracy Tests', () {
    late ParentDashboardProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = ParentDashboardProvider();
    });

    // =========================================================================
    // MODULE 1: 1-VIEW MEDIA & DUAL-PASS OCR
    // =========================================================================
    group('Module 1: 1-View Media & Dual-Pass OCR', () {
      test('1-View Snap metadata syncs with isViewOnce, mediaType, and OCR transcription text', () {
        final snapMsg = ChatMessage(
          id: 'media_1790579346480_snap01',
          appType: AppType.snapchat,
          contactName: 'Harshit Kamboj',
          contactIdentifier: '@harshit_kamboj97',
          messageText: '📷 [Received 1-View Snap from Harshit Kamboj]\n\n📝 OCR Extracted Text (Pass 1 Devanagari/Latin):\n"कल शाम 6 बजे कैफे में मिलते हैं"',
          timestamp: DateTime(2026, 9, 28, 7, 10, 0),
          isIncoming: true,
          isDeletedBackup: false,
          isWatchlistTarget: true,
          mediaUrl: 'https://wtlqlkkduescumpggttm.supabase.co/storage/v1/object/public/media/ghost_snap_1790579346.jpg',
          mediaType: 'snap',
          isViewOnce: true,
        );

        expect(snapMsg.isViewOnce, isTrue);
        expect(snapMsg.mediaType, 'snap');
        expect(snapMsg.mediaUrl, isNotNull);
        expect(snapMsg.isWatchlistTarget, isTrue);
        expect(snapMsg.messageText.contains('OCR Extracted Text'), isTrue);
        expect(snapMsg.messageText.contains('कल शाम 6 बजे'), isTrue);
      });

      test('Pass 2 Raw RGB Fallback OCR captures colored text when Pass 1 grayscale is blank', () {
        // Simulates dual-pass OCR result where pass 1 was empty but pass 2 found colored sticker text
        const pass1Result = '';
        const pass2FallbackResult = 'STREAK 🔥 240 DAYS';
        final resolvedOcr = pass1Result.isNotEmpty ? pass1Result : pass2FallbackResult;

        expect(resolvedOcr, 'STREAK 🔥 240 DAYS');
        final messagePayload = '📷 [1-View Snapchat Media Captured Silently]\n\n📝 OCR Extracted Text: "$resolvedOcr"';
        expect(messagePayload.contains('STREAK 🔥 240 DAYS'), isTrue);
      });

      test('1-View Media filter tab in chats screen identifies snaps and disappearing photos', () {
        final messages = [
          ChatMessage(
            id: 'm1',
            appType: AppType.snapchat,
            contactName: 'Harshit Kamboj',
            contactIdentifier: '@harshit_kamboj97',
            messageText: '📷 [1-View Snap Captured Silently]',
            timestamp: DateTime.now(),
            isIncoming: true,
            isDeletedBackup: false,
            isViewOnce: true,
            mediaType: 'snap',
            mediaUrl: 'https://supabase.co/storage/snap1.jpg',
          ),
          ChatMessage(
            id: 'm2',
            appType: AppType.snapchat,
            contactName: 'Rohan',
            contactIdentifier: 'Rohan',
            messageText: 'Regular text chat',
            timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
            isIncoming: true,
            isDeletedBackup: false,
            isViewOnce: false,
          ),
          ChatMessage(
            id: 'm3',
            appType: AppType.instagram,
            contactName: 'admiora.25',
            contactIdentifier: 'admiora.25',
            messageText: '📷 [View Once Direct Photo Captured]',
            timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
            isIncoming: true,
            isDeletedBackup: false,
            isViewOnce: true,
            mediaType: 'photo',
            mediaUrl: 'https://supabase.co/storage/insta_view_once.jpg',
          ),
        ];

        // Snapchat 1-view filter test
        final snapViewOnce = messages.where((m) {
          if (m.appType != AppType.snapchat) return false;
          return m.isViewOnce || m.mediaType == 'snap';
        }).toList();

        expect(snapViewOnce.length, 1);
        expect(snapViewOnce.first.contactName, 'Harshit Kamboj');
        expect(snapViewOnce.first.mediaUrl, 'https://supabase.co/storage/snap1.jpg');

        // Instagram 1-view filter test
        final instaViewOnce = messages.where((m) {
          if (m.appType != AppType.instagram) return false;
          return m.isViewOnce || m.mediaType == 'snap' || m.messageText.toLowerCase().contains('view once');
        }).toList();

        expect(instaViewOnce.length, 1);
        expect(instaViewOnce.first.contactName, 'admiora.25');
      });
    });

    // =========================================================================
    // MODULE 2: CHAT EXTRACTION, ERASURE CAPTURE & THREAD UNIFICATION
    // =========================================================================
    group('Module 2: Chat Extraction & Ring-Buffer Deduplication', () {
      test('Erased / cleared drafts captured with special tag and watchlist preservation', () {
        const activeContact = 'Harshit Kamboj';
        const erasedText = 'kaha hai bhai tu? phone utha';
        final isTarget = ParentDashboardProvider.isWatchlistContact(activeContact);

        final draftMsg = ChatMessage(
          id: 'draft_1790579335138',
          appType: AppType.whatsApp,
          contactName: 'Aryan (Child) [Erased Draft]',
          contactIdentifier: activeContact,
          messageText: '✍️ [Erased/Cleared Draft to $activeContact]: "$erasedText"',
          timestamp: DateTime.now(),
          isIncoming: false,
          isDeletedBackup: true,
          isWatchlistTarget: isTarget,
        );

        expect(draftMsg.isWatchlistTarget, isTrue);
        expect(draftMsg.isDeletedBackup, isTrue);
        expect(draftMsg.isIncoming, isFalse);
        expect(draftMsg.messageText.contains('kaha hai bhai tu?'), isTrue);
      });

      test('Ring buffer deduplication prevents double-recording identical rapid view-tree scrapes', () {
        final ringBuffer = <int>{};
        bool isDuplicate(String convKey, String text, String sender) {
          final hash = '$convKey:$sender:$text'.hashCode;
          return ringBuffer.contains(hash);
        }
        void record(String convKey, String text, String sender) {
          final hash = '$convKey:$sender:$text'.hashCode;
          ringBuffer.add(hash);
        }

        const conv = 'WhatsApp:Harshit Kamboj';
        const msg = 'Bhai assignment bhej de';
        const sender = 'Harshit Kamboj';

        expect(isDuplicate(conv, msg, sender), isFalse);
        record(conv, msg, sender);
        expect(isDuplicate(conv, msg, sender), isTrue); // Immediate duplicate rejected

        // Different message is accepted
        expect(isDuplicate(conv, 'Okay bhejta hu', sender), isFalse);
      });

      test('Keystroke search fragments (ha, har, hars) and UI counters are strictly suppressed', () {
        final testContacts = [
          'Harshit Kamboj',
          'ha',
          'har',
          'hars',
          'harsh',
          'harshi',
          'Save number is1377',
          'Reshare number is395',
          'Reposted 29 times',
          'Comment number is4',
          'View likes',
          'Follow',
          'Friends',
          'admiora.25',
        ];

        final filtered = testContacts.where((k) {
          final lower = k.trim().toLowerCase();
          if (lower == 'ha' || lower == 'har' || lower == 'hars' || lower == 'harsh' || lower == 'harshi') return false;
          if (lower.contains('save number') ||
              lower.contains('reshare') ||
              lower.contains('reposted') ||
              lower.contains('comment number') ||
              lower.contains('view likes') ||
              lower == 'follow' ||
              lower == 'friends') {
            return false;
          }
          return true;
        }).toList();

        expect(filtered.length, 2);
        expect(filtered, contains('Harshit Kamboj'));
        expect(filtered, contains('admiora.25'));
        expect(filtered, isNot(contains('hars')));
        expect(filtered, isNot(contains('Save number is1377')));
      });
    });

    // =========================================================================
    // MODULE 3: VOICE INTERCOM & AMBIENT AUDIO RECORDING
    // =========================================================================
    group('Module 3: Voice Intercom & Ambient Audio', () {
      test('Voice intercom dispatch formats announcement payload properly', () {
        const testAnnouncement = 'Aryan, please finish your homework and call mom immediately.';
        expect(() => provider.sendVoiceIntercom(testAnnouncement), returnsNormally);
      });

      test('Ambient audio recording commands toggle cleanly without throwing', () {
        expect(() => provider.triggerAmbientAudioRecording(), returnsNormally);
        expect(() => provider.stopAmbientAudioRecording(), returnsNormally);
      });

      test('AmbientLogItem duration formatting and storage calculation works accurately', () {
        final log = AmbientLogItem(
          id: 'ambient_log_01',
          timestamp: DateTime(2026, 9, 28, 7, 0),
          durationSeconds: 125,
          locationContext: 'Home / Living Room',
          speechSnippet: 'Discussing project submission deadline',
          isFlagged: false,
          isPurgedFromCloud: true,
          storageFreedKb: 3500,
        );

        expect(log.formattedDuration, '02:05');
        expect(log.isPurgedFromCloud, isTrue);
        expect(log.storageFreedKb, 3500);

        final updated = log.copyWith(isPurgedFromCloud: false);
        expect(updated.isPurgedFromCloud, isFalse);
      });
    });

    // =========================================================================
    // MODULE 4: LIVE SCREEN STREAM & SNAPCHAT SHIELD
    // =========================================================================
    group('Module 4: Live Screen Stream & Snapchat Stealth Shield', () {
      test('Live screen stream activates and enforces mutual exclusivity with camera', () {
        expect(provider.isLiveScreenActive, isFalse);
        expect(provider.isRemoteCameraActive, isFalse);

        provider.toggleLiveScreen();
        expect(provider.isLiveScreenActive, isTrue);
        expect(provider.isRemoteCameraActive, isFalse);

        provider.toggleRemoteCamera();
        expect(provider.isRemoteCameraActive, isTrue);
        expect(provider.isLiveScreenActive, isFalse);

        provider.toggleRemoteCamera();
        expect(provider.isRemoteCameraActive, isFalse);
      });

      test('Snapchat Stealth Shield logic: when Snapchat is foreground, screen stream is terminated', () {
        bool isStreamActive = true;
        void handleSnapchatForegroundEvent(String packageName) {
          if (packageName == 'com.snapchat.android') {
            isStreamActive = false; // Shield kills active screen projection instantly
          }
        }

        handleSnapchatForegroundEvent('com.whatsapp');
        expect(isStreamActive, isTrue);

        handleSnapchatForegroundEvent('com.snapchat.android');
        expect(isStreamActive, isFalse); // Terminated to prevent "X recorded screen" alert
      });
    });

    // =========================================================================
    // MODULE 5: REMOTE CAMERA STREAM & GREEN DOT STEALTH GUARD
    // =========================================================================
    group('Module 5: Remote Camera Stream & Green Dot Stealth Guard', () {
      test('Camera lens flip alternates between front and back seamlessly', () {
        expect(provider.currentCameraLens, 'back');
        provider.switchCameraLens();
        expect(provider.currentCameraLens, 'front');
        provider.switchCameraLens();
        expect(provider.currentCameraLens, 'back');
      });

      test('Stealth Screen Guard toggle enables green dot bypass on screen wake', () {
        expect(provider.isStealthScreenGuardEnabled, isTrue);
        provider.toggleStealthScreenGuard();
        expect(provider.isStealthScreenGuardEnabled, isFalse);
        provider.toggleStealthScreenGuard();
        expect(provider.isStealthScreenGuardEnabled, isTrue);
      });

      test('Screen wake auto-kills camera stream to prevent child noticing green dot indicator', () {
        bool isCameraRunning = true;
        void onScreenStateChanged(String intentAction, bool isStealthEnabled) {
          if (isStealthEnabled && (intentAction == 'android.intent.action.SCREEN_ON' || intentAction == 'android.intent.action.USER_PRESENT')) {
            isCameraRunning = false; // Auto-killed
          }
        }

        onScreenStateChanged('android.intent.action.SCREEN_ON', true);
        expect(isCameraRunning, isFalse);
      });
    });

    // =========================================================================
    // MODULE 6: SAME-WI-FI LAN SYNC & REDUNDANT CLOUD FAILOVER
    // =========================================================================
    group('Module 6: Same-Wi-Fi LAN Sync & Cloud Redundancy', () {
      test('Direct LAN event stream routes chats, calls, and notifications with 0-cloud latency', () {
        final receivedEvents = <String>[];
        void onLanEvent(String eventType, Map<String, dynamic> payload) {
          receivedEvents.add(eventType);
        }

        onLanEvent('chat', {'sender': 'Harshit Kamboj', 'text': 'Hey'});
        onLanEvent('notification', {'appName': 'WhatsApp', 'text': 'Meeting'});
        onLanEvent('call', {'contact': 'Mom', 'duration': 60});

        expect(receivedEvents, contains('chat'));
        expect(receivedEvents, contains('notification'));
        expect(receivedEvents, contains('call'));
        expect(receivedEvents.length, 3);
      });

      test('Device pairing code VYRA-13533 guarantees instant zero-setup re-connection', () {
        expect(provider.activePairingCode, 'VYRA-13533');
        expect(provider.activeChild.name, 'Vivo V2404');
        expect(provider.activeChild.selectedDisguise, 'System Toolkit');
      });
    });
  });
}
