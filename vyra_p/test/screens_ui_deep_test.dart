import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vyra_p/providers/parent_dashboard_provider.dart';
import 'package:vyra_p/screens/ambient_logs_screen.dart';
import 'package:vyra_p/screens/calls_screen.dart';
import 'package:vyra_p/screens/chats_screen.dart';
import 'package:vyra_p/screens/watchlist_screen.dart';
import 'package:vyra_p/models/chat_message.dart';
import 'package:vyra_p/widgets/chat_bubble.dart';
import 'package:vyra_p/widgets/voice_intercom_sheet.dart';

Widget createTestApp(Widget child, ParentDashboardProvider provider) {
  return ChangeNotifierProvider<ParentDashboardProvider>.value(
    value: provider,
    child: MaterialApp(
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Parent App UI Screens Deep Widget Tests', () {
    late ParentDashboardProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = ParentDashboardProvider();
    });

    testWidgets('WatchlistScreen renders targets and priority badges accurately', (WidgetTester tester) async {
      provider.addWatchlistTarget('Harshit Kamboj', 'harshit_kamboj', 'Snapchat & Instagram');

      await tester.pumpWidget(createTestApp(const WatchlistScreen(), provider));
      await tester.pumpAndSettle();

      expect(find.text('Priority Watchlist'), findsOneWidget);
      expect(find.text('Harshit Kamboj'), findsWidgets);
      expect(find.text('Add Target'), findsOneWidget);
    });

    testWidgets('ChatsScreen renders app selector and search bar cleanly', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(const ChatsScreen(), provider));
      await tester.pumpAndSettle();

      expect(find.text('WhatsApp'), findsWidgets);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('CallsScreen renders call log records cleanly', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(const CallsScreen(), provider));
      await tester.pumpAndSettle();

      expect(find.text('Call Logs & Recordings'), findsOneWidget);
    });

    testWidgets('AmbientLogsScreen renders ambient audio log interface', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(const AmbientLogsScreen(), provider));
      await tester.pumpAndSettle();

      expect(find.text('Ambient Voice Intelligence'), findsOneWidget);
    });

    testWidgets('VoiceIntercomSheet renders microphone announcement controls', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(const VoiceIntercomSheet(), provider));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.record_voice_over), findsOneWidget);
      expect(find.textContaining('Live Voice Intercom'), findsOneWidget);
    });

    testWidgets('ChatBubble renders Incoming 1-View Snap with badge and OCR extracted text', (WidgetTester tester) async {
      final snapMessage = ChatMessage(
        id: 'snap_test_01',
        appType: AppType.snapchat,
        contactName: 'Harshit Kamboj',
        contactIdentifier: '@harshit_kamboj',
        messageText: '📷 [Received 1-View Snap from Harshit Kamboj]\n\n📝 OCR Extracted Text: "Secret notes"',
        timestamp: DateTime.now(),
        isIncoming: true,
        isDeletedBackup: false,
        isWatchlistTarget: true,
        isViewOnce: true,
        mediaType: 'snap',
      );

      await tester.pumpWidget(createTestApp(ChatBubble(message: snapMessage), provider));
      await tester.pumpAndSettle();

      expect(find.text('👁️ Incoming 1-View (Captured before vanishing)'), findsOneWidget);
      expect(find.textContaining('Secret notes'), findsOneWidget);
      expect(find.text('WATCHLIST'), findsOneWidget);
    });

    testWidgets('ChatBubble renders Outgoing 1-View Snap sent by child with badge', (WidgetTester tester) async {
      final outgoingSnap = ChatMessage(
        id: 'snap_outgoing_01',
        appType: AppType.snapchat,
        contactName: 'Aryan (Child)',
        contactIdentifier: 'Aryan',
        messageText: '📷 [Sent 1-View Snap to Harshit Kamboj]',
        timestamp: DateTime.now(),
        isIncoming: false,
        isDeletedBackup: false,
        isWatchlistTarget: false,
        isViewOnce: true,
        mediaType: 'snap',
      );

      await tester.pumpWidget(createTestApp(ChatBubble(message: outgoingSnap), provider));
      await tester.pumpAndSettle();

      expect(find.text('👁️ Outgoing 1-View (Sent by child)'), findsOneWidget);
      expect(find.text('Sent by Aryan (Child)'), findsOneWidget);
      expect(find.textContaining('Sent 1-View Snap to Harshit Kamboj'), findsOneWidget);
    });

    testWidgets('ChatBubble renders Erased Draft message accurately', (WidgetTester tester) async {
      final erasedDraft = ChatMessage(
        id: 'draft_test_01',
        appType: AppType.snapchat,
        contactName: 'Aryan (Child) [Erased Draft]',
        contactIdentifier: 'Harshit Kamboj',
        messageText: '✍️ [Erased/Cleared Draft to Harshit Kamboj]: "kaha hai bhai tu?"',
        timestamp: DateTime.now(),
        isIncoming: false,
        isDeletedBackup: true,
        isWatchlistTarget: true,
      );

      await tester.pumpWidget(createTestApp(ChatBubble(message: erasedDraft), provider));
      await tester.pumpAndSettle();

      expect(find.text('Deleted for Everyone (Saved by Vyra)'), findsOneWidget);
      expect(find.textContaining('kaha hai bhai tu?'), findsOneWidget);
      expect(find.text('Sent by Aryan (Child)'), findsOneWidget);
    });
  });
}
