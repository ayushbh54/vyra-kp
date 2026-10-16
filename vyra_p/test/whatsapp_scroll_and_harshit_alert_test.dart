import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vyra_p/models/chat_message.dart';
import 'package:vyra_p/models/call_record.dart';
import 'package:vyra_p/providers/parent_dashboard_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WhatsApp-Style Reverse Scroll & Harshit High Alert Tests', () {
    test('1. Messages sort newest-first and date separators show on oldest message of each day', () {
      final now = DateTime.now();
      final day1 = now.subtract(const Duration(days: 2));
      final day2 = now.subtract(const Duration(days: 1));
      final day3 = now;

      final messages = [
        ChatMessage(
          id: 'm1',
          appType: AppType.whatsApp,
          contactName: 'Harshit Kamboj',
          contactIdentifier: '@harshit_kamboj97',
          messageText: 'Day 1 msg',
          timestamp: day1,
          isIncoming: true,
        ),
        ChatMessage(
          id: 'm2',
          appType: AppType.whatsApp,
          contactName: 'Harshit Kamboj',
          contactIdentifier: '@harshit_kamboj97',
          messageText: 'Day 2 msg 1',
          timestamp: day2,
          isIncoming: false,
        ),
        ChatMessage(
          id: 'm3',
          appType: AppType.whatsApp,
          contactName: 'Harshit Kamboj',
          contactIdentifier: '@harshit_kamboj97',
          messageText: 'Day 2 msg 2',
          timestamp: day2.add(const Duration(hours: 1)),
          isIncoming: true,
        ),
        ChatMessage(
          id: 'm4',
          appType: AppType.whatsApp,
          contactName: 'Harshit Kamboj',
          contactIdentifier: '@harshit_kamboj97',
          messageText: 'Day 3 msg latest',
          timestamp: day3,
          isIncoming: false,
        ),
      ];

      // Sort newest-first (b.timestamp.compareTo(a.timestamp))
      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Index 0 must be the newest message (anchored at bottom in ListView reverse: true)
      expect(messages.first.id, equals('m4'));
      expect(messages.last.id, equals('m1'));

      bool isSameDay(DateTime a, DateTime b) {
        return a.year == b.year && a.month == b.month && a.day == b.day;
      }

      // Check which indices should show a date separator in reverse mode
      final dateHeaderIndices = <int>[];
      for (int i = 0; i < messages.length; i++) {
        final showDateSeparator = i == messages.length - 1 ||
            !isSameDay(messages[i + 1].timestamp, messages[i].timestamp);
        if (showDateSeparator) {
          dateHeaderIndices.add(i);
        }
      }

      // In reverse mode:
      // index 0 is m4 (Day 3) -> next is m3 (Day 2) -> different day! Show header for Day 3!
      // index 1 is m3 (Day 2) -> next is m2 (Day 2) -> same day -> no header
      // index 2 is m2 (Day 2) -> next is m1 (Day 1) -> different day! Show header for Day 2!
      // index 3 is m1 (Day 1) -> last item -> Show header for Day 1!
      expect(dateHeaderIndices, equals([0, 2, 3]));
    });

    test('2. ParentDashboardProvider restores local cache unconditionally even if saved_children is empty', () async {
      SharedPreferences.setMockInitialValues({
        'cache_chats_VYRA-13533': [
          '{"id":"local_c1","appType":"whatsApp","contactName":"Harshit Kamboj","contactIdentifier":"@harshit_kamboj97","messageText":"Hey Aryan","timestamp":"2026-10-15T12:00:00.000Z","isIncoming":true,"isDeletedBackup":false,"isWatchlistTarget":true,"isViewOnce":false}'
        ],
        'cache_calls_VYRA-13533': [
          '{"id":"local_call1","contactName":"Harshit","phoneNumber":"+919876543210","callType":"incoming","timestamp":"2026-10-15T11:00:00.000Z","durationSeconds":120,"isTamperAttemptDetected":false,"isWatchlistTarget":true}'
        ],
        'cache_notifs_VYRA-13533': [
          '{"id":"local_n1","packageName":"com.snapchat.android","appName":"Snapchat","title":"Harshit Kamboj","message":"Sent a chat","timestamp":"2026-10-15T12:05:00.000Z","isSensitiveAlert":true}'
        ],
      });

      final provider = ParentDashboardProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify cached records loaded into provider immediately
      expect(provider.allArchivedChatMessages.any((m) => m.id == 'local_c1'), isTrue);
      expect(provider.callRecords.any((c) => c.id == 'local_call1'), isTrue);
      expect(provider.notifications.any((n) => n.id == 'local_n1'), isTrue);
    });

    test('3. Harshit Kamboj Watchdog flags target and adds to Watchlist', () {
      expect(ParentDashboardProvider.isWatchlistContact('Harshit'), isTrue);
      expect(ParentDashboardProvider.isWatchlistContact('Harshit kamboj'), isTrue);
      expect(ParentDashboardProvider.isWatchlistContact('@harshit_kamboj97'), isTrue);
      expect(ParentDashboardProvider.isWatchlistContact('harshit.kamboj'), isTrue);
      expect(ParentDashboardProvider.isWatchlistContact('Aman Sharma'), isFalse);

      expect(ParentDashboardProvider.normalizeContactName('Harshit'), equals('Harshit Kamboj'));
      expect(ParentDashboardProvider.normalizeContactName('Harshit kamboj'), equals('Harshit Kamboj'));
      expect(ParentDashboardProvider.normalizeContactName('harshit_kamboj97'), equals('Harshit Kamboj'));
    });

    test('4. Scraper garbage filtering eliminates noise without affecting legitimate messages', () {
      expect(ParentDashboardProvider.isScraperGarbage('Tap to load'), isTrue);
      expect(ParentDashboardProvider.isScraperGarbage('Delivered'), isTrue);
      expect(ParentDashboardProvider.isScraperGarbage('Seen 2m ago'), isTrue);
      expect(ParentDashboardProvider.isScraperGarbage('Typing...'), isTrue);
      expect(ParentDashboardProvider.isScraperGarbage('9:41 AM'), isTrue);
      expect(ParentDashboardProvider.isScraperGarbage('78%'), isTrue);
      expect(ParentDashboardProvider.isScraperGarbage('Hi Harshit kaise ho?'), isFalse);
      expect(ParentDashboardProvider.isScraperGarbage('Photo bhej rha hu dekh le'), isFalse);
    });
  });
}
