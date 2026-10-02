class NotificationItem {
  final String id;
  final String packageName;
  final String appName;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isDeletedBackup;
  final bool isSensitiveAlert;

  const NotificationItem({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isDeletedBackup = false,
    this.isSensitiveAlert = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'packageName': packageName,
    'appName': appName,
    'title': title,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
    'isDeletedBackup': isDeletedBackup,
    'isSensitiveAlert': isSensitiveAlert,
  };

  factory NotificationItem.fromJson(Map<String, dynamic> json) => NotificationItem(
    id: json['id'] ?? '',
    packageName: json['packageName'] ?? '',
    appName: json['appName'] ?? '',
    title: json['title'] ?? '',
    message: json['message'] ?? '',
    timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
    isDeletedBackup: json['isDeletedBackup'] as bool? ?? false,
    isSensitiveAlert: json['isSensitiveAlert'] as bool? ?? false,
  );
}
