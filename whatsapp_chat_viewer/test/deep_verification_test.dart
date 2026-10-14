import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vyra_chat_viewer/models/whatsapp_message.dart';
import 'package:vyra_chat_viewer/providers/whatsapp_viewer_provider.dart';
import 'package:vyra_chat_viewer/screens/whatsapp_import_screen.dart';
import 'package:vyra_chat_viewer/services/local_backup_importer.dart';
import 'package:vyra_chat_viewer/services/whatsapp_crypt_service.dart';
import 'package:vyra_chat_viewer/services/whatsapp_sanitizer.dart';
import 'package:vyra_chat_viewer/services/whatsapp_sqlite_service.dart';
import 'package:vyra_chat_viewer/widgets/chat_bubble.dart';
import 'package:vyra_chat_viewer/widgets/floating_deleted_notch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('1. WhatsApp Cryptographic Engine Deep Tests', () {
    test('64-hex key validation & conversion', () {
      const validHex = 'a1b2c3d4e5f60718293a4b5c6d7e8f90123456789abcdef0123456789abcdef0';
      final bytes = WhatsAppCryptService.parseHexKey(validHex);
      expect(bytes.length, 32);
      expect(bytes[0], 0xa1);
      expect(bytes[1], 0xb2);
      expect(bytes[31], 0xf0);

      // Invalid length should throw FormatException
      expect(
        () => WhatsAppCryptService.parseHexKey('a1b2c3'),
        throwsFormatException,
      );
    });

    test('Crypt15 HKDF key expansion is deterministic', () {
      final rootKey = Uint8List.fromList(List.generate(32, (i) => i));
      final derivedKey1 = WhatsAppCryptService.deriveCrypt15Key(rootKey);
      final derivedKey2 = WhatsAppCryptService.deriveCrypt15Key(rootKey);

      expect(derivedKey1.length, 32);
      expect(derivedKey1, equals(derivedKey2));
      // Derived key must not be identical to root key (due to HMAC-SHA256 expansion)
      expect(derivedKey1, isNot(equals(rootKey)));
    });

    test('158-byte WhatsApp key file parsing', () {
      final keyFileBytes = Uint8List(158);
      // Place known 32-byte key at offset 30..62
      for (int i = 0; i < 32; i++) {
        keyFileBytes[30 + i] = i + 10;
      }
      final extractedKey = WhatsAppCryptService.parseKeyFile(keyFileBytes);
      expect(extractedKey.length, 32);
      expect(extractedKey[0], 10);
      expect(extractedKey[31], 41);
    });

    test('Zlib decompression of compressed SQLite payload', () {
      const testString = 'SQLite format 3\u0000Test WhatsApp Database Content';
      final rawBytes = utf8.encode(testString);
      final compressed = ZLibEncoder().encode(rawBytes);

      expect(compressed.length, isPositive);
      final decompressed = ZLibDecoder().decodeBytes(compressed);
      expect(utf8.decode(decompressed), testString);
      expect(WhatsAppCryptService.isUnencryptedSqlite(Uint8List.fromList(decompressed)), isTrue);
    });
  });

  group('2. SQLite Schema & WhatsApp Parser Deep Tests', () {
    late Database testDb;
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wa_test_');
      dbFile = File('${tempDir.path}/msgstore.db');
      testDb = await databaseFactory.openDatabase(dbFile.path);

      // Create realistic modern WhatsApp SQLite schema
      await testDb.execute('''
        CREATE TABLE jid (
          _id INTEGER PRIMARY KEY,
          raw_string TEXT NOT NULL
        );
      ''');
      await testDb.execute('''
        CREATE TABLE chat (
          _id INTEGER PRIMARY KEY,
          jid_row_id INTEGER NOT NULL,
          subject TEXT,
          sort_timestamp INTEGER,
          unseen_message_count INTEGER DEFAULT 0
        );
      ''');
      await testDb.execute('''
        CREATE TABLE message (
          _id INTEGER PRIMARY KEY,
          chat_row_id INTEGER NOT NULL,
          from_me INTEGER NOT NULL,
          timestamp INTEGER NOT NULL,
          text_data TEXT,
          message_type INTEGER NOT NULL,
          status INTEGER DEFAULT 0,
          sender_jid_row_id INTEGER
        );
      ''');

      // Populate test data
      // Contact 1: Individual chat (+91 98765 43210)
      await testDb.insert('jid', {'_id': 1, 'raw_string': '919876543210@s.whatsapp.net'});
      await testDb.insert('chat', {
        '_id': 1,
        'jid_row_id': 1,
        'subject': null,
        'sort_timestamp': 1700000000000,
        'unseen_message_count': 2,
      });

      // Contact 2: School Group
      await testDb.insert('jid', {'_id': 2, 'raw_string': '12036302@g.us'});
      await testDb.insert('chat', {
        '_id': 2,
        'jid_row_id': 2,
        'subject': 'Class 10 Study Group',
        'sort_timestamp': 1700000050000,
        'unseen_message_count': 0,
      });

      // Insert Messages into Chat 1 (Individual)
      // Normal incoming message
      await testDb.insert('message', {
        '_id': 101,
        'chat_row_id': 1,
        'from_me': 0,
        'timestamp': 1700000000000,
        'text_data': 'Hello brother! Are you home?',
        'message_type': 0,
      });
      // Outgoing message
      await testDb.insert('message', {
        '_id': 102,
        'chat_row_id': 1,
        'from_me': 1,
        'timestamp': 1700000010000,
        'text_data': 'Yes, just reached.',
        'message_type': 0,
      });
      // Revoked/Deleted message by sender (type 15)
      await testDb.insert('message', {
        '_id': 103,
        'chat_row_id': 1,
        'from_me': 0,
        'timestamp': 1700000020000,
        'text_data': 'This message was deleted',
        'message_type': 15,
      });

      // Insert Messages into Chat 2 (Group)
      await testDb.insert('message', {
        '_id': 201,
        'chat_row_id': 2,
        'from_me': 0,
        'timestamp': 1700000040000,
        'text_data': 'Exam timetable is out!',
        'message_type': 0,
      });
      // Revoked message in Group (type 15)
      await testDb.insert('message', {
        '_id': 202,
        'chat_row_id': 2,
        'from_me': 0,
        'timestamp': 1700000050000,
        'text_data': 'This message was deleted',
        'message_type': 15,
      });

      await testDb.close();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('WhatsAppSqliteService accurately loads conversations & flags deleted counts', () async {
      final sqliteService = WhatsAppSqliteService();
      await sqliteService.openDatabaseFile(dbFile);

      expect(sqliteService.isOpen, isTrue);

      final conversations = await sqliteService.fetchConversations();
      expect(conversations.length, 2);

      // Verify Group chat
      final groupConv = conversations.firstWhere((c) => c.isGroup);
      expect(groupConv.name, 'Class 10 Study Group');
      expect(groupConv.deletedCount, 1);

      // Verify Individual chat
      final individualConv = conversations.firstWhere((c) => !c.isGroup);
      expect(individualConv.name, '+91 98765 43210');
      expect(individualConv.unreadCount, 2);
      expect(individualConv.deletedCount, 1);

      await sqliteService.closeDatabase();
    });

    test('WhatsAppSqliteService fetches message thread with in-place deleted flag', () async {
      final sqliteService = WhatsAppSqliteService();
      await sqliteService.openDatabaseFile(dbFile);

      final messages = await sqliteService.fetchMessagesForConversation('919876543210@s.whatsapp.net');
      expect(messages.length, 3);

      expect(messages[0].text, 'Hello brother! Are you home?');
      expect(messages[0].isIncoming, isTrue);
      expect(messages[0].isDeleted, isFalse);

      expect(messages[1].text, 'Yes, just reached.');
      expect(messages[1].isIncoming, isFalse);
      expect(messages[1].isFromChild, isTrue);
      expect(messages[1].isDeleted, isFalse);

      expect(messages[2].text, 'This message was deleted');
      expect(messages[2].isDeleted, isTrue);
      expect(messages[2].isDeletedBySender, isTrue);

      await sqliteService.closeDatabase();
    });

    test('WhatsAppSqliteService fetchAllDeletedMessages aggregates all deleted across threads', () async {
      final sqliteService = WhatsAppSqliteService();
      await sqliteService.openDatabaseFile(dbFile);

      final allDeleted = await sqliteService.fetchAllDeletedMessages();
      expect(allDeleted.length, 2);

      expect(allDeleted.every((m) => m.isDeleted), isTrue);

      await sqliteService.closeDatabase();
    });
  });

  group('3. WhatsApp Sanitizer & Import Tests', () {
    test('Cleans system buttons and noise', () {
      expect(WhatsAppSanitizer.isGarbage('Read more'), isTrue);
      expect(WhatsAppSanitizer.isGarbage('Your personal messages are end-to-end encrypted'), isTrue);
      expect(WhatsAppSanitizer.isGarbage('2131232237'), isTrue);
      expect(WhatsAppSanitizer.isGarbage('Just now'), isTrue);
      expect(WhatsAppSanitizer.isGarbage('Bhai kal tuition chalna hai?'), isFalse);
    });

    test('Parses group sender prefix correctly', () {
      final parsed = WhatsAppSanitizer.parseMessage('Group', '~ Rohit: Kal physics ka test hai', false);
      expect(parsed.sender, 'Rohit');
      expect(parsed.cleanText, 'Kal physics ka test hai');
      expect(parsed.isDeleted, isFalse);
    });

    test('Parses exported chat txt format with deleted lines', () {
      const sampleExport = '''
12/10/26, 10:30 AM - Harshit: Hello bhai
12/10/26, 10:31 AM - You: Ha bolo
12/10/26, 10:32 AM - Harshit: This message was deleted
''';
      final messages = LocalBackupImporter.parseExportedChatTxt(sampleExport, defaultContact: 'Harshit');
      expect(messages.length, 3);
      expect(messages[0].text, 'Hello bhai');
      expect(messages[1].isIncoming, isFalse);
      expect(messages[2].isDeleted, isTrue);
    });
  });

  group('4. UI & Widget Deep Tests', () {
    testWidgets('Renders WhatsAppImportScreen with file picker and 64-hex key input', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider(
            create: (_) => WhatsAppViewerProvider(),
            child: const WhatsAppImportScreen(),
          ),
        ),
      );

      expect(find.text('WhatsApp Viewer & Decryptor'), findsOneWidget);
      expect(find.text('1. Select WhatsApp Backup or Database'), findsOneWidget);
      expect(find.text('2. Decryption Key (64-Hex or key file)'), findsOneWidget);
      expect(find.text('Decrypt & View Chats'), findsOneWidget);
    });

    testWidgets('ChatBubble displays red in-place deleted banner when message is deleted', (tester) async {
      final deletedMessage = WhatsAppMessage(
        id: '1',
        sender: 'Aman',
        text: 'This message was deleted',
        timestamp: DateTime.now(),
        isIncoming: true,
        isDeleted: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WhatsAppChatBubble(message: deletedMessage),
          ),
        ),
      );

      expect(find.text('Deleted by Sender (Captured)'), findsOneWidget);
      expect(find.text('This message was deleted'), findsOneWidget);
    });

    testWidgets('FloatingDeletedNotch renders badge counter and responds to tap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                FloatingDeletedNotch(
                  count: 7,
                  onTap: () => tapped = true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('7 msgs'), findsOneWidget);
      expect(find.text('DELETED'), findsOneWidget);
      await tester.tap(find.byType(FloatingDeletedNotch));
      expect(tapped, isTrue);
    });
  });
}
