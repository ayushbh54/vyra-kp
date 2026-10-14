import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vyra_chat_viewer/main.dart';
import 'package:vyra_chat_viewer/providers/whatsapp_viewer_provider.dart';
import 'package:vyra_chat_viewer/services/whatsapp_crypt_service.dart';
import 'package:vyra_chat_viewer/services/whatsapp_sanitizer.dart';

void main() {
  testWidgets('WhatsAppViewerApp opens on dedicated Decryptor screen when clean', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => WhatsAppViewerProvider()),
        ],
        child: const WhatsAppViewerApp(),
      ),
    );

    // Verify WhatsApp Viewer & Decryptor title is present
    expect(find.text('WhatsApp Viewer & Decryptor'), findsOneWidget);
    // Verify 100% Offline WhatsApp Decryptor banner
    expect(find.text('100% Offline WhatsApp Decryptor'), findsOneWidget);
    // Verify Decrypt button
    expect(find.text('Decrypt & View Chats'), findsOneWidget);
  });

  group('WhatsAppCryptService tests', () {
    test('64-hex string parsed correctly to 32 bytes', () {
      const hexKey = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      final bytes = WhatsAppCryptService.parseHexKey(hexKey);
      expect(bytes.length, 32);
      expect(bytes[0], 0x01);
      expect(bytes[1], 0x23);
      expect(bytes[31], 0xef);
    });

    test('Crypt15 key derivation produces 32-byte AES key', () {
      final rootKey = Uint8List(32);
      final derived = WhatsAppCryptService.deriveCrypt15Key(rootKey);
      expect(derived.length, 32);
    });

    test('SQLite header magic recognition', () {
      final validSqliteHeader = Uint8List.fromList([
        0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
        0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00,
        0x01, 0x02,
      ]);
      expect(WhatsAppCryptService.isUnencryptedSqlite(validSqliteHeader), isTrue);

      final randomBytes = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      expect(WhatsAppCryptService.isUnencryptedSqlite(randomBytes), isFalse);
    });
  });

  group('WhatsAppSanitizer tests', () {
    test('Group tilde prefix extraction', () {
      final parsed = WhatsAppSanitizer.parseMessage('Group', '~ Rahul: Aaj cricket khelenge?', false);
      expect(parsed.sender, 'Rahul');
      expect(parsed.cleanText, 'Aaj cricket khelenge?');
      expect(parsed.isDeleted, isFalse);
    });

    test('Deleted message detection', () {
      final parsed = WhatsAppSanitizer.parseMessage('Aman', 'This message was deleted', false);
      expect(parsed.isDeleted, isTrue);
    });
  });
}
