class AlertBannerData {
  final String title;
  final String message;
  final String appName;
  final String? contactName;
  final DateTime timestamp;

  const AlertBannerData({
    required this.title,
    required this.message,
    required this.appName,
    this.contactName,
    required this.timestamp,
  });
}
