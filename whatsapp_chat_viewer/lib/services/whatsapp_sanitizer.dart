import 'package:flutter/material.dart';

class ParsedMessage {
  final String sender;
  final String cleanText;
  final bool isDeleted;

  const ParsedMessage({
    required this.sender,
    required this.cleanText,
    required this.isDeleted,
  });
}

class WhatsAppSanitizer {
  /// Cleans out scraper garbage, system buttons, and UI artifacts
  static String cleanText(String text) {
    if (isGarbage(text)) return '';
    return text.trim();
  }

  static bool isGarbage(String text) {
    final t = text.trim();
    if (t.length < 2) return true;

    // View IDs (e.g. 2131232237)
    if (RegExp(r'^\d{6,}$').hasMatch(t)) return true;

    final lower = t.toLowerCase();

    // Encryption notices
    if (lower.contains('end-to-end encrypted') ||
        lower.contains('end to end encrypted') ||
        lower.contains('messages and calls are end-to-end') ||
        lower.contains('your personal messages are end-to-end')) {
      return true;
    }

    // Android/WhatsApp Action Buttons & Navigation artifacts
    const junkWords = {
      'copy', 'copy code', 'copy otp', 'reply', 'delete', 'delete message',
      'forward', 'share', 'mark as read', 'clear all', 'dismiss', 'view details',
      'report', 'block', 'done', 'cancel', 'install', 'update', 'open',
      'messages', 'all messages', 'conversations', 'select', 'select all',
      'unread', 'read', 'read more', 'group settings', 'go to most recent message',
      'open voice chat', 'only admins can send messages', 'message your assistant',
      'tap for more info', 'info', 'turn on notifications', 'never miss snaps',
      'add friends', 'find friends', 'search', 'search...', 'phone', 'video call',
      'voice call', 'camera', 'more options', 'back', 'type a message', 'message',
      'stickers', 'emoji', 'attach', 'disappearing messages', 'chat', 'chats',
      'calls', 'updates', 'communities', 'status', 'online', 'typing...'
    };
    if (junkWords.contains(lower)) return true;
    if (lower.contains("you'll get notifications only for @mentions")) return true;
    if (RegExp(r'^\d+\s+unread\s+messages?$', caseSensitive: false).hasMatch(t)) return true;

    // Relative timestamps
    if (RegExp(r'^\d+\s*(?:second|sec|minute|min|hour|hr|day|week|month)s?\s*(?:ago)?$', caseSensitive: false).hasMatch(t)) {
      return true;
    }
    if (lower == 'just now' || lower == 'today' || lower == 'yesterday' || lower == 'now') {
      return true;
    }
    if (RegExp(r'^\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)?$').hasMatch(t)) return true;
    if (RegExp(r'^\d{1,2}/\d{1,2}/\d{2,4}$').hasMatch(t)) return true;

    // Standalone SMS shortcodes / OTP blocks
    if (RegExp(r'^[A-Z]{2}-[A-Z0-9]{4,10}$', caseSensitive: false).hasMatch(t)) return true;
    if (RegExp(r'^\d{3}\s+\d{3}$').hasMatch(t)) return true;
    if (RegExp(r'^\d{4,8}$').hasMatch(t)) return true;

    return false;
  }

  /// Parses WhatsApp group message syntax (~ Contact Name: message) and detects deleted flags
  static ParsedMessage parseMessage(String rawSender, String rawText, bool rawDeleted) {
    String text = rawText.trim();
    String sender = rawSender.trim();
    bool isDeleted = rawDeleted;

    final lowerText = text.toLowerCase();
    if (lowerText.contains('this message was deleted') ||
        lowerText.contains('you deleted this message') ||
        lowerText.contains('message deleted by sender') ||
        lowerText.contains('[deleted by sender]')) {
      isDeleted = true;
      if (text.length < 45) {
        text = '🚫 This message was deleted by sender (Preserved)';
      }
    }

    // Detect Snapchat erased typing draft
    if (text.startsWith('[👻 SNAPCHAT TYPING DRAFT]:')) {
      isDeleted = true;
    }

    // WhatsApp group message prefix: "~ Sonia: Hello everyone"
    final tildeMatch = RegExp(r'^~\s*([^:]+):\s*(.*)$', dotAll: true).firstMatch(text);
    if (tildeMatch != null) {
      final extracted = tildeMatch.group(1)?.trim() ?? '';
      final body = tildeMatch.group(2)?.trim() ?? '';
      if (extracted.isNotEmpty &&
          !extracted.toLowerCase().contains('team id') &&
          !extracted.toLowerCase().contains('team name')) {
        sender = extracted;
        text = body.isNotEmpty ? body : text;
      }
    }

    return ParsedMessage(
      sender: sender.isEmpty ? 'Unknown' : sender,
      cleanText: text,
      isDeleted: isDeleted,
    );
  }

  /// Authentic WhatsApp group sender colors
  static final List<Color> _participantColors = [
    const Color(0xFF1F8AFF), // Blue
    const Color(0xFF25D366), // Green
    const Color(0xFFFF9800), // Orange
    const Color(0xFFE91E63), // Pink
    const Color(0xFF9C27B0), // Purple
    const Color(0xFF00BCD4), // Cyan
    const Color(0xFFFF5722), // Deep Orange
    const Color(0xFFFFC107), // Amber
  ];

  static Color getParticipantColor(String name) {
    if (name.isEmpty) return _participantColors[0];
    final hash = name.codeUnits.fold(0, (prev, curr) => prev + curr);
    return _participantColors[hash % _participantColors.length];
  }
}
