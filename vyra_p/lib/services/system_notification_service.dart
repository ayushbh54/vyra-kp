import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service that interacts with native iOS / Android system notification managers
/// to display authentic OS-level notifications on the lock screen and notification center
/// even when the parent app is closed or backgrounded.
class SystemNotificationService {
  static final SystemNotificationService instance = SystemNotificationService._internal();

  SystemNotificationService._internal();

  static const MethodChannel _channel = MethodChannel('com.vyra.parent/notifications');
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final granted = await _channel.invokeMethod<bool>('requestPermissions');
      _initialized = true;
      debugPrint('SystemNotificationService: Permissions granted: $granted');
    } catch (e) {
      debugPrint('SystemNotificationService: Error initializing permissions: $e');
    }
  }

  /// Posts a real OS system notification to the phone's notification shade & lock screen with sound
  Future<void> showNotification({
    required String id,
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    try {
      await _channel.invokeMethod('showSystemNotification', {
        'id': id,
        'title': title,
        'body': body,
        if (payload != null) ...payload,
      });
      debugPrint('SystemNotificationService: Presented system notification "$title"');
    } catch (e) {
      debugPrint('SystemNotificationService: Failed to show system notification: $e');
    }
  }
}
