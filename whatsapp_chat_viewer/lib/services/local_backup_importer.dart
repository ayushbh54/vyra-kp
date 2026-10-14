import 'dart:convert';
import 'package:intl/intl.dart';
import '../models/whatsapp_message.dart';
import 'whatsapp_sanitizer.dart';

class LocalBackupImporter {
  static List<WhatsAppMessage> parseTxtExport(String content, {String defaultSender = 'Imported Chat'}) {
    return parseExportedChatTxt(content, defaultContact: defaultSender);
  }

  /// Parses standard exported WhatsApp chat text files
  /// Example lines:
  /// 12/10/26, 10:30 AM - Harshit Kamboj: Hey bro
  /// [12/10/2026, 10:32:00] Harshit: This message was deleted
  static List<WhatsAppMessage> parseExportedChatTxt(String content, {String defaultContact = 'Imported Chat'}) {
    final lines = content.split('\n');
    final messages = <WhatsAppMessage>[];

    final regex1 = RegExp(r'^(\d{1,2}/\d{1,2}/\d{2,4}),?\s+(\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)\s*-\s*([^:]+):\s*(.*)$');
    final regex2 = RegExp(r'^\[(\d{1,2}/\d{1,2}/\d{2,4}),?\s+(\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)\]\s*([^:]+):\s*(.*)$');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      Match? match = regex1.firstMatch(line) ?? regex2.firstMatch(line);
      if (match != null) {
        final dateStr = match.group(1)!;
        final timeStr = match.group(2)!;
        final sender = match.group(3)!.trim();
        final rawText = match.group(4)!.trim();

        DateTime timestamp = DateTime.now();
        try {
          final dtStr = "$dateStr $timeStr";
          timestamp = DateFormat("d/M/y h:mm a").parse(dtStr);
        } catch (_) {
          try {
            timestamp = DateFormat("M/d/yy, h:mm a").parse("$dateStr, $timeStr");
          } catch (_) {}
        }

        final parsed = WhatsAppSanitizer.parseMessage(sender, rawText, false);

        messages.add(WhatsAppMessage(
          id: 'imp_${DateTime.now().millisecondsSinceEpoch}_$i',
          threadId: defaultContact,
          contactName: defaultContact,
          sender: parsed.sender,
          text: parsed.cleanText,
          timestamp: timestamp,
          isIncoming: parsed.sender != 'You',
          isDeleted: parsed.isDeleted,
        ));
      } else if (messages.isNotEmpty) {
        // Multi-line message continuation
        final last = messages.last;
        messages[messages.length - 1] = WhatsAppMessage(
          id: last.id,
          threadId: last.threadId,
          contactName: last.contactName,
          sender: last.sender,
          text: '${last.text}\n$line',
          timestamp: last.timestamp,
          isIncoming: last.isIncoming,
          isDeleted: last.isDeleted,
        );
      }
    }

    return messages;
  }

  /// Parses JSON backup dump of chats
  static List<WhatsAppMessage> parseJsonDump(String jsonContent) {
    try {
      final parsed = jsonDecode(jsonContent);
      if (parsed is! List) return [];

      final results = <WhatsAppMessage>[];
      for (final item in parsed) {
        if (item is Map) {
          results.add(WhatsAppMessage.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      return results;
    } catch (_) {
      return [];
    }
  }
}
