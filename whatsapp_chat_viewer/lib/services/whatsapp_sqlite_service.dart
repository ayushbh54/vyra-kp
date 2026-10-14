import 'dart:io';
import 'package:sqflite/sqflite.dart';
import '../models/whatsapp_conversation.dart';
import '../models/whatsapp_message.dart';
import 'whatsapp_sanitizer.dart';

class WhatsAppSqliteService {
  Database? _db;
  String? _currentPath;

  bool get isOpen => _db != null && _db!.isOpen;
  String? get currentPath => _currentPath;

  /// Open WhatsApp SQLite database file
  Future<void> openDatabaseFile(File sqliteFile) async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
    }
    _db = await openReadOnlyDatabase(sqliteFile.path);
    _currentPath = sqliteFile.path;
  }

  /// Close active database
  Future<void> closeDatabase() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
      _currentPath = null;
    }
  }

  /// Check which tables exist in this WhatsApp database
  Future<List<String>> getExistingTables() async {
    if (_db == null) return [];
    final rows = await _db!.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' OR type='view';",
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Fetch all conversation threads from the WhatsApp database
  Future<List<WhatsAppConversation>> fetchConversations() async {
    if (_db == null) return [];
    final tables = await getExistingTables();
    final hasModernChat = tables.contains('chat') && tables.contains('jid');

    if (hasModernChat) {
      return _fetchModernConversations();
    } else if (tables.contains('chat_list') || tables.contains('messages')) {
      return _fetchLegacyConversations();
    } else if (tables.contains('message_view')) {
      return _fetchFromMessageView();
    }
    return [];
  }

  /// Modern WhatsApp schema (v2.20 - v2.26+)
  Future<List<WhatsAppConversation>> _fetchModernConversations() async {
    final query = '''
      SELECT 
        c._id AS chat_id,
        j.raw_string AS jid,
        c.subject AS group_subject,
        c.sort_timestamp AS last_timestamp,
        c.unseen_message_count AS unseen_count,
        (
          SELECT m.text_data 
          FROM message m 
          WHERE m.chat_row_id = c._id AND m.text_data IS NOT NULL 
          ORDER BY m.timestamp DESC LIMIT 1
        ) AS last_text,
        (
          SELECT COUNT(*) 
          FROM message m 
          WHERE m.chat_row_id = c._id AND (m.message_type = 15 OR m.text_data LIKE '%This message was deleted%')
        ) AS deleted_count
      FROM chat c
      LEFT JOIN jid j ON c.jid_row_id = j._id
      WHERE j.raw_string IS NOT NULL
      ORDER BY c.sort_timestamp DESC
    ''';

    try {
      final rows = await _db!.rawQuery(query);
      final List<WhatsAppConversation> conversations = [];

      for (final row in rows) {
        final jid = (row['jid'] as String?) ?? '';
        final subject = (row['group_subject'] as String?) ?? '';
        final displayName = _formatDisplayName(jid, subject);
        final isGroup = jid.endsWith('@g.us');
        final lastTimeMs = (row['last_timestamp'] as int?) ?? 0;
        final lastMsg = (row['last_text'] as String?) ?? '';
        final deletedCount = (row['deleted_count'] as int?) ?? 0;
        final unseenCount = (row['unseen_count'] as int?) ?? 0;

        conversations.add(
          WhatsAppConversation(
            id: jid,
            name: displayName,
            phoneNumber: isGroup ? '' : _formatPhoneNumber(jid),
            isGroup: isGroup,
            unreadCount: unseenCount,
            lastMessageText: WhatsAppSanitizer.cleanText(lastMsg),
            lastMessageTime: DateTime.fromMillisecondsSinceEpoch(
              lastTimeMs > 0 ? lastTimeMs : DateTime.now().millisecondsSinceEpoch,
            ),
            deletedCount: deletedCount,
          ),
        );
      }
      return conversations;
    } catch (_) {
      return _fetchFromMessageView();
    }
  }

  /// Legacy WhatsApp schema
  Future<List<WhatsAppConversation>> _fetchLegacyConversations() async {
    try {
      final query = '''
        SELECT 
          key_remote_jid AS jid,
          MAX(timestamp) AS last_timestamp,
          data AS last_text,
          COUNT(CASE WHEN message_type = 15 OR data LIKE '%This message was deleted%' THEN 1 END) AS deleted_count
        FROM messages
        WHERE key_remote_jid IS NOT NULL
        GROUP BY key_remote_jid
        ORDER BY last_timestamp DESC
      ''';
      final rows = await _db!.rawQuery(query);
      return rows.map((r) {
        final jid = r['jid'] as String;
        final isGroup = jid.endsWith('@g.us');
        final ts = (r['last_timestamp'] as int?) ?? 0;
        return WhatsAppConversation(
          id: jid,
          name: _formatDisplayName(jid, null),
          phoneNumber: isGroup ? '' : _formatPhoneNumber(jid),
          isGroup: isGroup,
          lastMessageText: WhatsAppSanitizer.cleanText((r['last_text'] as String?) ?? ''),
          lastMessageTime: DateTime.fromMillisecondsSinceEpoch(ts),
          deletedCount: (r['deleted_count'] as int?) ?? 0,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fallback using message_view
  Future<List<WhatsAppConversation>> _fetchFromMessageView() async {
    try {
      final query = '''
        SELECT 
          chat_row_id,
          MAX(timestamp) AS last_timestamp,
          text_data,
          from_me
        FROM message_view
        GROUP BY chat_row_id
        ORDER BY last_timestamp DESC
      ''';
      final rows = await _db!.rawQuery(query);
      return rows.map((r) {
        final chatId = (r['chat_row_id'] as int).toString();
        final ts = (r['last_timestamp'] as int?) ?? 0;
        return WhatsAppConversation(
          id: chatId,
          name: "Chat #$chatId",
          phoneNumber: '',
          isGroup: false,
          lastMessageText: WhatsAppSanitizer.cleanText((r['text_data'] as String?) ?? ''),
          lastMessageTime: DateTime.fromMillisecondsSinceEpoch(ts),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch full message history for a specific conversation
  Future<List<WhatsAppMessage>> fetchMessagesForConversation(String conversationId) async {
    if (_db == null) return [];
    final tables = await getExistingTables();

    if (tables.contains('message') && tables.contains('jid')) {
      final query = '''
        SELECT 
          m._id AS msg_id,
          m.from_me,
          m.timestamp,
          m.text_data,
          m.message_type,
          m.status,
          sender_jid.raw_string AS sender_jid
        FROM message m
        JOIN chat c ON m.chat_row_id = c._id
        JOIN jid chat_jid ON c.jid_row_id = chat_jid._id
        LEFT JOIN jid sender_jid ON m.sender_jid_row_id = sender_jid._id
        WHERE chat_jid.raw_string = ? OR c._id = ?
        ORDER BY m.timestamp ASC
      ''';

      try {
        final rows = await _db!.rawQuery(query, [conversationId, int.tryParse(conversationId) ?? -1]);
        return rows.map((r) => _mapRowToMessage(r, conversationId)).toList();
      } catch (_) {
        // Fallback to simpler query
      }
    }

    if (tables.contains('messages')) {
      final query = '''
        SELECT 
          _id AS msg_id,
          key_from_me AS from_me,
          timestamp,
          data AS text_data,
          status,
          media_wa_type AS message_type
        FROM messages
        WHERE key_remote_jid = ?
        ORDER BY timestamp ASC
      ''';
      try {
        final rows = await _db!.rawQuery(query, [conversationId]);
        return rows.map((r) => _mapRowToMessage(r, conversationId)).toList();
      } catch (_) {}
    }

    return [];
  }

  /// Fetch all deleted/erased messages across the entire WhatsApp database
  Future<List<WhatsAppMessage>> fetchAllDeletedMessages({int limit = 500}) async {
    if (_db == null) return [];
    final tables = await getExistingTables();

    if (tables.contains('message') && tables.contains('chat') && tables.contains('jid')) {
      final query = '''
        SELECT 
          m._id AS msg_id,
          m.from_me,
          m.timestamp,
          m.text_data,
          m.message_type,
          chat_jid.raw_string AS chat_jid,
          c.subject AS group_subject,
          sender_jid.raw_string AS sender_jid
        FROM message m
        JOIN chat c ON m.chat_row_id = c._id
        JOIN jid chat_jid ON c.jid_row_id = chat_jid._id
        LEFT JOIN jid sender_jid ON m.sender_jid_row_id = sender_jid._id
        WHERE m.message_type = 15 
           OR m.text_data LIKE '%This message was deleted%'
           OR m.text_data LIKE '%You deleted this message%'
        ORDER BY m.timestamp DESC
        LIMIT ?
      ''';

      try {
        final rows = await _db!.rawQuery(query, [limit]);
        return rows.map((r) {
          final chatJid = (r['chat_jid'] as String?) ?? '';
          final subject = (r['group_subject'] as String?) ?? '';
          final contactTitle = _formatDisplayName(chatJid, subject);
          return _mapRowToMessage(r, chatJid, overrideSender: contactTitle);
        }).toList();
      } catch (_) {}
    }

    return [];
  }

  WhatsAppMessage _mapRowToMessage(
    Map<String, Object?> r,
    String chatJid, {
    String? overrideSender,
  }) {
    final fromMe = ((r['from_me'] as int?) ?? 0) == 1;
    final type = (r['message_type'] as int?) ?? 0;
    final rawText = (r['text_data'] as String?) ?? '';
    final isRevoked = type == 15 ||
        rawText.contains('This message was deleted') ||
        rawText.contains('You deleted this message');

    final ts = (r['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
    final senderJid = (r['sender_jid'] as String?) ?? '';

    String senderDisplay = overrideSender ?? (fromMe ? 'You' : _formatDisplayName(senderJid.isNotEmpty ? senderJid : chatJid, null));

    String content = rawText;
    if (isRevoked && (content.isEmpty || content.contains('deleted'))) {
      content = "This message was deleted";
    } else if (content.isEmpty) {
      content = _mediaTypeLabel(type);
    }

    return WhatsAppMessage(
      id: (r['msg_id'] as int).toString(),
      threadId: chatJid,
      contactName: overrideSender ?? '',
      sender: senderDisplay,
      text: WhatsAppSanitizer.cleanText(content),
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
      isIncoming: !fromMe,
      isDeleted: isRevoked,
      isViewOnce: type == 1 && rawText.isEmpty,
      mediaType: _mediaTypeName(type),
    );
  }

  String _formatDisplayName(String jid, String? groupSubject) {
    if (groupSubject != null && groupSubject.isNotEmpty) {
      return groupSubject;
    }
    if (jid.endsWith('@g.us')) {
      return "Group (${jid.split('@').first})";
    }
    return _formatPhoneNumber(jid);
  }

  String _formatPhoneNumber(String jid) {
    final num = jid.split('@').first;
    if (num.length >= 10 && RegExp(r'^\d+$').hasMatch(num)) {
      if (num.length == 12 && num.startsWith('91')) {
        return "+91 ${num.substring(2, 7)} ${num.substring(7)}";
      }
      return "+$num";
    }
    return num;
  }

  String _mediaTypeLabel(int type) {
    switch (type) {
      case 1:
        return "📷 Photo";
      case 2:
        return "🎵 Voice Note / Audio";
      case 3:
        return "🎥 Video";
      case 5:
        return "📍 Location";
      case 9:
        return "📄 Document";
      case 15:
        return "🚫 This message was deleted";
      default:
        return "💬 Message";
    }
  }

  String _mediaTypeName(int type) {
    switch (type) {
      case 1:
        return "image";
      case 2:
        return "audio";
      case 3:
        return "video";
      case 9:
        return "document";
      default:
        return "text";
    }
  }
}
