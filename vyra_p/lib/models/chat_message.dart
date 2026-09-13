enum AppType {
  whatsApp,
  instagram,
  telegram,
  sms,
}

enum ChatDateRange {
  last2Days,
  last7Days,
  last30Days,
  allTime,
}

extension ChatDateRangeExtension on ChatDateRange {
  String get label {
    switch (this) {
      case ChatDateRange.last2Days:
        return 'Last 2 Days';
      case ChatDateRange.last7Days:
        return 'Last 7 Days';
      case ChatDateRange.last30Days:
        return 'Last 30 Days';
      case ChatDateRange.allTime:
        return 'All Time';
    }
  }

  int get daysBack {
    switch (this) {
      case ChatDateRange.last2Days:
        return 2;
      case ChatDateRange.last7Days:
        return 7;
      case ChatDateRange.last30Days:
        return 30;
      case ChatDateRange.allTime:
        return 90;
    }
  }
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
