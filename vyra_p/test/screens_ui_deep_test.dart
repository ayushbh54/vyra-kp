import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vyra_p/providers/parent_dashboard_provider.dart';
import 'package:vyra_p/screens/ambient_logs_screen.dart';
import 'package:vyra_p/screens/calls_screen.dart';
import 'package:vyra_p/screens/chats_screen.dart';
import 'package:vyra_p/screens/watchlist_screen.dart';
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
  });
}
