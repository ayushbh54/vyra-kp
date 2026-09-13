enum CallType {
  incoming,
  outgoing,
  missed,
}

class CallRecord {
  final String id;
  final String contactName;
  final String phoneNumber;
  final CallType callType;
  final DateTime timestamp;
  final int durationSeconds;
  final String? recordingUrl;
  final int? recordingDurationSeconds;
  final bool isTamperAttemptDetected;
  final bool isWatchlistTarget;

  const CallRecord({
    required this.id,
    required this.contactName,
    required this.phoneNumber,
    required this.callType,
    required this.timestamp,
    required this.durationSeconds,
    this.recordingUrl,
    this.recordingDurationSeconds,
    this.isTamperAttemptDetected = false,
    this.isWatchlistTarget = false,
  });

  String get formattedDuration {
    final mins = durationSeconds ~/ 60;
    final secs = durationSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
