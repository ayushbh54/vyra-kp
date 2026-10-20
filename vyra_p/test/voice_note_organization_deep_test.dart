import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vyra_p/models/chat_message.dart';
import 'package:vyra_p/models/chat_conversation.dart';
import 'package:vyra_p/providers/parent_dashboard_provider.dart';
import 'package:vyra_p/widgets/chat_bubble.dart';
import 'package:vyra_p/services/audio_playback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = null;
  });

  group('Voice Note Organization & In-line Playback Deep End-to-End Suite', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ParentDashboardProvider.isTesting = true;
    });

    tearDown(() {
      ParentDashboardProvider.isTesting = false;
    });

    test('1. Voice notes strictly group into their specific contact conversation threads', () {
      // Simulate Realtime/Supabase voice notes for 3 different contacts
      final aditiVoice = ChatMessage(
        id: 'voice_aditi_101',
        appType: AppType.whatsApp,
        contactName: 'Aditi 💗',
        contactIdentifier: 'Aditi 💗',
        messageText: '🎤 Voice message (17s)',
        timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        isIncoming: true,
        voiceNoteUrl: 'https://drive.usercontent.google.com/download?id=1test_aditi_voice&export=download',
        voiceNoteDurationSeconds: 17,
        mediaType: 'audio',
      );

      final aliyaVoice = ChatMessage(
        id: 'voice_aliya_202',
        appType: AppType.instagram,
        contactName: 'Aliya Iran',
        contactIdentifier: 'Aliya Iran',
        messageText: '🎤 Voice message (43s)',
        timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
        isIncoming: true,
        voiceNoteUrl: 'https://drive.usercontent.google.com/download?id=1test_aliya_voice&export=download',
        voiceNoteDurationSeconds: 43,
        mediaType: 'audio',
      );

      final harshitVoice = ChatMessage(
        id: 'voice_harshit_303',
        appType: AppType.whatsApp,
        contactName: 'Harshit Kamboj',
        contactIdentifier: '@harshit_kamboj97',
        messageText: '🎤 Voice message (35s)',
        timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
        isIncoming: true,
        isWatchlistTarget: true,
        voiceNoteUrl: 'https://drive.usercontent.google.com/download?id=1test_harshit_voice&export=download',
        voiceNoteDurationSeconds: 35,
        mediaType: 'audio',
      );

      final allMessages = [aditiVoice, aliyaVoice, harshitVoice];

      // Grouping logic matching ChatsScreen
      final grouped = <String, List<ChatMessage>>{};
      for (final m in allMessages) {
        final key = m.contactIdentifier.isNotEmpty ? m.contactIdentifier : m.contactName;
        grouped.putIfAbsent(key, () => []).add(m);
      }

      final conversations = grouped.entries.map((entry) {
        final msgs = entry.value;
        return ChatConversation(
          contactIdentifier: entry.key,
          contactName: msgs.first.contactName,
          appType: msgs.first.appType,
          messages: msgs,
          isWatchlistTarget: msgs.any((m) => m.isWatchlistTarget),
        );
      }).toList();

      expect(conversations.length, equals(3));

      final aditiConv = conversations.firstWhere((c) => c.contactName == 'Aditi 💗');
      expect(aditiConv.messages.any((m) => m.id == 'voice_aditi_101'), isTrue);
      expect(aditiConv.messages.first.voiceNoteDurationSeconds, equals(17));
      expect(aditiConv.messages.first.mediaType, equals('audio'));

      final aliyaConv = conversations.firstWhere((c) => c.contactName == 'Aliya Iran');
      expect(aliyaConv.messages.any((m) => m.id == 'voice_aliya_202'), isTrue);
      expect(aliyaConv.messages.first.voiceNoteDurationSeconds, equals(43));

      final harshitConv = conversations.firstWhere((c) => c.contactName == 'Harshit Kamboj');
      expect(harshitConv.messages.any((m) => m.id == 'voice_harshit_303'), isTrue);
      expect(harshitConv.isWatchlistTarget, isTrue);
    });

    test('2. AudioPlaybackService properly normalizes Drive & Supabase voice note URLs', () {
      const driveUrl = 'https://drive.google.com/uc?export=download&id=1lkI8vDOlMD3T2Bqqj0UQVM4G4Gqct4lh';
      final normDrive = AudioPlaybackService.normalizeAudioUrl(driveUrl);
      expect(normDrive, equals('https://drive.usercontent.google.com/download?id=1lkI8vDOlMD3T2Bqqj0UQVM4G4Gqct4lh&export=download'));

      const directCdn = 'https://drive.usercontent.google.com/download?id=1lkI8vDOlMD3T2Bqqj0UQVM4G4Gqct4lh&export=download';
      final normDirect = AudioPlaybackService.normalizeAudioUrl(directCdn);
      expect(normDirect, equals(directCdn));

      const legacySupabase = 'https://wtlqlkkduescumpggttm.supabase.co/storage/v1/object/public/recordings/VYRA-13533/voice_test.opus';
      final normSupabase = AudioPlaybackService.normalizeAudioUrl(legacySupabase);
      expect(normSupabase, contains('/recordings/VYRA-13533/voice_test.opus'));
    });

    testWidgets('3. ChatBubble renders in-line functional voice player bar with duration and play button', (tester) async {
      final provider = ParentDashboardProvider();

      final voiceMessage = ChatMessage(
        id: 'voice_msg_1792500173',
        appType: AppType.whatsApp,
        contactName: 'Aditi 💗',
        contactIdentifier: 'Aditi 💗',
        messageText: '🎤 Voice message (17s)',
        timestamp: DateTime.now(),
        isIncoming: true,
        voiceNoteUrl: 'https://drive.usercontent.google.com/download?id=1test_voice_id&export=download',
        voiceNoteDurationSeconds: 17,
        mediaType: 'audio',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ParentDashboardProvider>.value(
            value: provider,
            child: Scaffold(
              body: ChatBubble(
                message: voiceMessage,
              ),
            ),
          ),
        ),
      );

      // Verify in-line voice note text and duration
      expect(find.text('Voice Note (17s)'), findsOneWidget);

      // Verify Play icon is present
      expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);

      // Tap Play button and verify provider triggers playback
      await tester.tap(find.byIcon(Icons.play_circle_fill_rounded));
      await tester.pump();

      expect(provider.currentlyPlayingAudioId, equals('voice_msg_1792500173'));
    });

    testWidgets('4. Outgoing voice note renders aligned to the right as sent by child', (tester) async {
      final provider = ParentDashboardProvider();

      final sentVoiceMessage = ChatMessage(
        id: 'voice_sent_1792500174',
        appType: AppType.whatsApp,
        contactName: 'Aditi 💗',
        contactIdentifier: 'Aditi 💗',
        messageText: '🎤 Voice message (12s)',
        timestamp: DateTime.now(),
        isIncoming: false, // Outgoing / Sent by child
        voiceNoteUrl: 'https://drive.usercontent.google.com/download?id=1test_sent_id&export=download',
        voiceNoteDurationSeconds: 12,
        mediaType: 'audio',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ParentDashboardProvider>.value(
            value: provider,
            child: Scaffold(
              body: ChatBubble(
                message: sentVoiceMessage,
              ),
            ),
          ),
        ),
      );

      // Verify duration
      expect(find.text('Voice Note (12s)'), findsOneWidget);

      // Outgoing bubble aligns to the right
      final alignFinder = find.byType(Align);
      expect(alignFinder, findsWidgets);
      final alignWidget = tester.widget<Align>(alignFinder.first);
      expect(alignWidget.alignment, equals(Alignment.centerRight));
    });
  });
}
