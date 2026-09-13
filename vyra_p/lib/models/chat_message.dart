enum AppType {
  whatsApp,
  instagram,
  telegram,
  sms,
}

extension AppTypeExtension on AppType {
  String get displayName {
    switch (this) {
      case AppType.whatsApp:
        return 'WhatsApp';
      case AppType.instagram:
        return 'Instagram';
      case AppType.telegram:
        return 'Telegram';
      case AppType.sms:
        return 'SMS';
    }
  }

  String get iconAsset {
    switch (this) {
      case AppType.whatsApp:
        return '💬';
      case AppType.instagram:
        return '📸';
      case AppType.telegram:
        return '✈️';
      case AppType.sms:
        return '✉️';
    }
  }
}

class ChatMessage {
  final String id;
  final AppType appType;
  final String contactName;
  final String contactIdentifier; // Phone number or @handle
  final String messageText;
  final DateTime timestamp;
  final bool isIncoming;
  final bool isDeletedBackup; // Preserved even if sender deleted it
  final bool isWatchlistTarget;
  final String? voiceNoteUrl;
  final int? voiceNoteDurationSeconds;

  const ChatMessage({
    required this.id,
    required this.appType,
    required this.contactName,
    required this.contactIdentifier,
    required this.messageText,
    required this.timestamp,
    required this.isIncoming,
    this.isDeletedBackup = false,
    this.isWatchlistTarget = false,
    this.voiceNoteUrl,
    this.voiceNoteDurationSeconds,
  });
}
