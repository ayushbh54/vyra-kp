import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vyra_p/providers/parent_dashboard_provider.dart';
import 'package:vyra_p/screens/watchlist_screen.dart';
import 'package:vyra_p/screens/main_navigation_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Deep Watchlist & Instant Alert Verification Suite', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('1. isWatchlistContact and isWatchlistMatch detect Harshit/Kamboj in contact name or message text', () {
      // Direct name match
      expect(ParentDashboardProvider.isWatchlistContact('Harshit Kamboj'), isTrue);
      expect(ParentDashboardProvider.isWatchlistContact('harshit'), isTrue);
      expect(ParentDashboardProvider.isWatchlistContact('kamboj97'), isTrue);

      // Contact name is neutral, but message text mentions Harshit
      expect(ParentDashboardProvider.isWatchlistContact('Rohit Sharma', 'kal Harshit se mile the kya?'), isTrue);
      expect(ParentDashboardProvider.isWatchlistContact('Random Contact', 'contact kamboj brother'), isTrue);
      expect(ParentDashboardProvider.isWatchlistContact('Random Contact', 'normal chat without keywords'), isFalse);

      final provider = ParentDashboardProvider();
      // Instance isWatchlistMatch
      expect(provider.isWatchlistMatch('Aman', 'harshit ko bol dena'), isTrue);
      expect(provider.isWatchlistMatch('Aman', 'meet at 5 pm'), isFalse);
    });

    test('2. Watchlist target addition, removal, and persistence', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ParentDashboardProvider();

      final initialCount = provider.watchlistTargets.length;
      expect(initialCount, greaterThanOrEqualTo(1)); // pre-seeded Harshit Kamboj

      // Add custom target
      provider.addWatchlistTarget('Suspicious Friend', '@suspicious_user', 'Met at club');
      expect(provider.watchlistTargets.length, initialCount + 1);
      final addedTarget = provider.watchlistTargets.firstWhere((t) => t.name == 'Suspicious Friend');
      expect(addedTarget.identifier, '@suspicious_user');

      // isWatchlistMatch should now match this newly added target
      expect(provider.isWatchlistMatch('Suspicious Friend', 'hello'), isTrue);
      expect(provider.isWatchlistMatch('Other Person', 'ask @suspicious_user'), isTrue);

      // Now remove the custom target
      provider.removeWatchlistTarget(addedTarget.id);
      expect(provider.watchlistTargets.any((t) => t.id == addedTarget.id), isFalse);
      expect(provider.watchlistTargets.length, initialCount);

      // After removal, should no longer match
      expect(provider.isWatchlistMatch('Suspicious Friend', 'hello'), isFalse);
    });

    test('3. High priority alert trigger and activeAlertBanner emission', () {
      final provider = ParentDashboardProvider();
      expect(provider.activeAlertBanner.value, isNull);

      provider.triggerWatchlistAlert(
        title: '🚨 HIGH ALERT: Harshit Activity',
        message: 'WHATSAPP (Rohit): "harshit ne call kiya tha"',
        appName: 'WhatsApp',
        contactName: 'Rohit',
      );

      final alert = provider.activeAlertBanner.value;
      expect(alert, isNotNull);
      expect(alert!.title, contains('HIGH ALERT'));
      expect(alert.message, contains('harshit'));
      expect(alert.appName, 'WhatsApp');
      expect(alert.contactName, 'Rohit');

      // Dismiss alert
      provider.dismissAlertBanner();
      expect(provider.activeAlertBanner.value, isNull);
    });

    testWidgets('4. WatchlistScreen displays Remove Target button and dialog confirmation', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final provider = ParentDashboardProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ParentDashboardProvider>.value(
            value: provider,
            child: const WatchlistScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the delete button
      final deleteBtn = find.byIcon(Icons.delete_outline);
      expect(deleteBtn, findsWidgets);

      // Tap delete button on the first target
      await tester.tap(deleteBtn.first);
      await tester.pumpAndSettle();

      // Verify remove confirmation dialog is shown
      expect(find.text('Remove from Watchlist?'), findsOneWidget);
      expect(find.text('Remove Target'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tap Remove Target
      await tester.tap(find.text('Remove Target'));
      await tester.pumpAndSettle();

      // Target should be removed
      expect(find.text('Remove from Watchlist?'), findsNothing);
    });

    testWidgets('5. MainNavigationShell displays animated Heads-Up Push Notification Banner on Harshit alert', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final provider = ParentDashboardProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ParentDashboardProvider>.value(
            value: provider,
            child: const MainNavigationShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no banner
      expect(find.byIcon(Icons.warning_rounded), findsNothing);

      // Fire alert
      provider.triggerWatchlistAlert(
        title: '🚨 HIGH ALERT: Harshit Kamboj',
        message: 'SNAPCHAT: "1-view snap captured"',
        appName: 'Snapchat',
        contactName: 'Harshit Kamboj',
      );
      await tester.pumpAndSettle();

      // Banner should now be visible on top of screen
      expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
      expect(find.text('🚨 HIGH ALERT: Harshit Kamboj'), findsOneWidget);
      expect(find.text('SNAPCHAT: "1-view snap captured"'), findsOneWidget);

      // Tap dismiss (close button)
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('🚨 HIGH ALERT: Harshit Kamboj'), findsNothing);
    });
  });
}
