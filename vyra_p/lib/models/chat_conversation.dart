import 'chat_message.dart';

class ChatConversation {
  final String contactIdentifier;
  final String contactName;
  final AppType appType;
  final List<ChatMessage> messages;
  final bool isWatchlistTarget;

  ChatConversation({
    required this.contactIdentifier,
    required this.contactName,
    required this.appType,
    required this.messages,
    required this.isWatchlistTarget,
  });

  ChatMessage get lastMessage => messages.first;
  int get totalMessages => messages.length;
  bool get hasDeletedBackup => messages.any((m) => m.isDeletedBackup);
}
