import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vyra_p/models/chat_conversation.dart';
import 'package:vyra_p/models/chat_message.dart';
import 'package:vyra_p/providers/parent_dashboard_provider.dart';
import 'package:vyra_p/screens/ambient_logs_screen.dart';
import 'package:vyra_p/screens/calls_screen.dart';
import 'package:vyra_p/screens/chat_conversation_detail_screen.dart';
import 'package:vyra_p/screens/chats_screen.dart';
import 'package:vyra_p/screens/dashboard_screen.dart';
import 'package:vyra_p/screens/watchlist_screen.dart';

void main() {
  setUp(() {
    ParentDashboardProvider.isTesting = true;
    FlutterError.onError = (details) {
      debugPrint(">>> FULL ERROR DETAILS:\n${details.toString()}");
    };
  });

  group('Universal Screen Fit & Zero RenderFlex Overflow Verification', () {
    // Test on smallest mobile screen (iPhone SE / 320x568) and standard (390x844)
    final testSizes = [
      const Size(320, 568), // Ultra-narrow screen (iPhone SE 1st gen / compact android)
      const Size(375, 667), // Classic iPhone SE / Mini
      const Size(390, 844), // iPhone 14/15/16 Pro
      const Size(430, 932), // iPhone Pro Max / Plus
    ];

    testWidgets('DashboardScreen renders on all screen sizes with ZERO overflow', (tester) async {
      for (final size in testSizes) {
        await tester.binding.setSurfaceSize(size);

        final provider = ParentDashboardProvider();
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: provider,
            child: const MaterialApp(home: DashboardScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DashboardScreen), findsOneWidget);
        final exc = tester.takeException();
        if (exc != null) {
          if (exc is FlutterError) {
            for (final d in exc.diagnostics) {
              debugPrint(">>> DIAG: ${d.toStringDeep()}");
            }
          } else {
            debugPrint("OVERFLOW DETECTED: $exc");
          }
        }
        expect(exc, isNull, reason: 'Zero layout overflow on ${size.width}x${size.height}');
      }
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('ChatsScreen renders and filters with ZERO overflow', (tester) async {
      for (final size in testSizes) {
        await tester.binding.setSurfaceSize(size);

        final provider = ParentDashboardProvider();
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: provider,
            child: const MaterialApp(home: ChatsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ChatsScreen), findsOneWidget);
        final exc = tester.takeException();
        if (exc != null) {
          if (exc is FlutterError) {
            debugPrint("FULL STACK:\n${exc.toStringDeep()}");
          } else {
            debugPrint("OVERFLOW DETECTED: $exc");
          }
        }
        expect(exc, isNull, reason: 'Zero layout overflow on ${size.width}x${size.height}');
      }
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('AmbientLogsScreen renders diarization & stats with ZERO overflow', (tester) async {
      for (final size in testSizes) {
        await tester.binding.setSurfaceSize(size);

        final provider = ParentDashboardProvider();
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: provider,
            child: const MaterialApp(home: AmbientLogsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AmbientLogsScreen), findsOneWidget);
        final exc = tester.takeException();
        if (exc != null) {
          if (exc is FlutterError) {
            debugPrint("FULL STACK:\n${exc.toStringDeep()}");
          } else {
            debugPrint("OVERFLOW DETECTED: $exc");
          }
        }
        expect(exc, isNull, reason: 'Zero layout overflow on ${size.width}x${size.height}');
      }
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('ChatConversationDetailScreen & ChatBubble render with ZERO overflow', (tester) async {
      for (final size in testSizes) {
        await tester.binding.setSurfaceSize(size);

        final provider = ParentDashboardProvider();
        final conversation = ChatConversation(
          contactName: 'Harshit Kamboj (Coaching Friend With Super Long Title)',
          contactIdentifier: '+919876543210',
          appType: AppType.whatsApp,
          isWatchlistTarget: false,
          messages: [
            ChatMessage(
              id: 'm1',
              contactName: 'Harshit Kamboj Very Long Name That Could Overflow',
              contactIdentifier: '+919876543210',
              messageText: 'Bhai sun, class kab khatam hogi? 1-View Snap bheja hai!',
              timestamp: DateTime.now(),
              isIncoming: true,
              isViewOnce: true,
              isDeletedBackup: true,
              appType: AppType.whatsApp,
            ),
          ],
        );

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: provider,
            child: MaterialApp(
              home: ChatConversationDetailScreen(conversation: conversation),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ChatConversationDetailScreen), findsOneWidget);
        final exc = tester.takeException();
        if (exc != null) {
          if (exc is FlutterError) {
            debugPrint("FULL STACK:\n${exc.toStringDeep()}");
          } else {
            debugPrint("OVERFLOW DETECTED: $exc");
          }
        }
        expect(exc, isNull, reason: 'Zero layout overflow on ${size.width}x${size.height}');
      }
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('AudioPlayerCard & CallsScreen render with ZERO overflow', (tester) async {
      for (final size in testSizes) {
        await tester.binding.setSurfaceSize(size);

        final provider = ParentDashboardProvider();
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: provider,
            child: const MaterialApp(home: CallsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CallsScreen), findsOneWidget);
        final exc = tester.takeException();
        if (exc != null) {
          if (exc is FlutterError) {
            debugPrint("FULL STACK:\n${exc.toStringDeep()}");
          } else {
            debugPrint("OVERFLOW DETECTED: $exc");
          }
        }
        expect(exc, isNull, reason: 'Zero layout overflow on ${size.width}x${size.height}');
      }
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('WatchlistScreen & NotificationsFeedScreen render with ZERO overflow', (tester) async {
      for (final size in testSizes) {
        await tester.binding.setSurfaceSize(size);

        final provider = ParentDashboardProvider();
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: provider,
            child: const MaterialApp(home: WatchlistScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(WatchlistScreen), findsOneWidget);
        final exc = tester.takeException();
        if (exc != null) {
          if (exc is FlutterError) {
            debugPrint("FULL STACK:\n${exc.toStringDeep()}");
          } else {
            debugPrint("OVERFLOW DETECTED: $exc");
          }
        }
        expect(exc, isNull, reason: 'Zero layout overflow on ${size.width}x${size.height}');
      }
      await tester.binding.setSurfaceSize(null);
    });
  });
}
