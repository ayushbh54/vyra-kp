enum AppType {
  whatsApp,
  instagram,
  telegram,
  snapchat,
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
      case AppType.snapchat:
        return 'Snapchat';
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
      case AppType.snapchat:
        return '👻';
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
  final String? mediaUrl;
  final String? mediaType; // 'image', 'video', 'snap'
  final bool isViewOnce;
  final bool isDualVerified;

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
    this.mediaUrl,
    this.mediaType,
    this.isViewOnce = false,
    this.isDualVerified = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'appType': appType.name,
    'contactName': contactName,
    'contactIdentifier': contactIdentifier,
    'messageText': messageText,
    'timestamp': timestamp.toIso8601String(),
    'isIncoming': isIncoming,
    'isDeletedBackup': isDeletedBackup,
    'isWatchlistTarget': isWatchlistTarget,
    'voiceNoteUrl': voiceNoteUrl,
    'voiceNoteDurationSeconds': voiceNoteDurationSeconds,
    'mediaUrl': mediaUrl,
    'mediaType': mediaType,
    'isViewOnce': isViewOnce,
    'isDualVerified': isDualVerified,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    AppType app = AppType.whatsApp;
    final appName = json['appType']?.toString().toLowerCase() ?? '';
    for (final t in AppType.values) {
      if (t.name.toLowerCase() == appName) {
        app = t;
        break;
      }
    }

    return ChatMessage(
      id: json['id'] ?? '',
      appType: app,
      contactName: json['contactName'] ?? 'Unknown',
      contactIdentifier: json['contactIdentifier'] ?? '',
      messageText: json['messageText'] ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      isIncoming: json['isIncoming'] as bool? ?? true,
      isDeletedBackup: json['isDeletedBackup'] as bool? ?? false,
      isWatchlistTarget: json['isWatchlistTarget'] as bool? ?? false,
      voiceNoteUrl: json['voiceNoteUrl'],
      voiceNoteDurationSeconds: (json['voiceNoteDurationSeconds'] as num?)?.toInt(),
      mediaUrl: json['mediaUrl'],
      mediaType: json['mediaType'],
      isViewOnce: json['isViewOnce'] as bool? ?? false,
      isDualVerified: json['isDualVerified'] as bool? ?? false,
    );
  }
}

class ParsedChatMessage {
  final String sender;
  final String cleanText;
  final bool isDeleted;

  const ParsedChatMessage({
    required this.sender,
    required this.cleanText,
    required this.isDeleted,
  });
}
