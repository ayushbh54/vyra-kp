import 'whatsapp_message.dart';

class WhatsAppConversation {
  final String id;
  final String name;
  final String phoneNumber;
  final bool isGroup;
  final List<WhatsAppMessage> messages;
  final int unreadCount;
  final int deletedCount;
  final String? lastMessageText;
  final DateTime? lastMessageTime;

  const WhatsAppConversation({
    required this.id,
    required this.name,
    this.phoneNumber = '',
    required this.isGroup,
    this.messages = const [],
    this.unreadCount = 0,
    this.deletedCount = 0,
    this.lastMessageText,
    this.lastMessageTime,
  });

  String get contactName => name;

  WhatsAppMessage get lastMessage => messages.isNotEmpty
      ? messages.first
      : WhatsAppMessage(
          id: '',
          threadId: id,
          contactName: name,
          sender: name,
          text: lastMessageText ?? 'No messages',
          timestamp: lastMessageTime ?? DateTime.now(),
          isIncoming: true,
          isDeleted: false,
        );
}
