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
}
