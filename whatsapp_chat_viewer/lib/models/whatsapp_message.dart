class WhatsAppMessage {
  final String id;
  final String threadId;
  final String contactName;
  final String sender;
  final String text;
  final DateTime timestamp;
  final bool isIncoming;
  final bool isDeleted;
  final bool isGroup;
  final String? mediaUrl;
  final String? mediaType;
  final bool isViewOnce;

  const WhatsAppMessage({
    required this.id,
    this.threadId = '',
    this.contactName = '',
    required this.sender,
    required this.text,
    required this.timestamp,
    required this.isIncoming,
    required this.isDeleted,
    this.isGroup = false,
    this.mediaUrl,
    this.mediaType,
    this.isViewOnce = false,
  });

  bool get isFromChild => !isIncoming;
  bool get isDeletedBySender => isDeleted;

  Map<String, dynamic> toJson() => {
    'id': id,
    'threadId': threadId,
    'contactName': contactName,
    'sender': sender,
    'text': text,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'isIncoming': isIncoming,
    'isDeleted': isDeleted,
    'isGroup': isGroup,
    'mediaUrl': mediaUrl,
    'mediaType': mediaType,
    'isViewOnce': isViewOnce,
  };

  factory WhatsAppMessage.fromJson(Map<String, dynamic> json) => WhatsAppMessage(
    id: json['id']?.toString() ?? '',
    threadId: json['threadId']?.toString() ?? '',
    contactName: json['contactName']?.toString() ?? 'Contact',
    sender: json['sender']?.toString() ?? '',
    text: json['text']?.toString() ?? '',
    timestamp: DateTime.fromMillisecondsSinceEpoch(
      (json['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    ),
    isIncoming: (json['isIncoming'] as bool?) ?? true,
    isDeleted: (json['isDeleted'] as bool?) ?? false,
    isGroup: (json['isGroup'] as bool?) ?? false,
    mediaUrl: json['mediaUrl']?.toString(),
    mediaType: json['mediaType']?.toString(),
    isViewOnce: (json['isViewOnce'] as bool?) ?? false,
  );
}
