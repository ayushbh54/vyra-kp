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

  Map<String, dynamic> toJson() => {
    'id': id,
    'contactName': contactName,
    'phoneNumber': phoneNumber,
    'callType': callType.name,
    'timestamp': timestamp.toIso8601String(),
    'durationSeconds': durationSeconds,
    'recordingUrl': recordingUrl,
    'recordingDurationSeconds': recordingDurationSeconds,
    'isTamperAttemptDetected': isTamperAttemptDetected,
    'isWatchlistTarget': isWatchlistTarget,
  };

  factory CallRecord.fromJson(Map<String, dynamic> json) {
    CallType cType = CallType.incoming;
    final typeStr = json['callType']?.toString().toLowerCase() ?? '';
    for (final t in CallType.values) {
      if (t.name.toLowerCase() == typeStr) {
        cType = t;
        break;
      }
    }

    return CallRecord(
      id: json['id'] ?? '',
      contactName: json['contactName'] ?? 'Unknown',
      phoneNumber: json['phoneNumber'] ?? '',
      callType: cType,
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      recordingUrl: json['recordingUrl'],
      recordingDurationSeconds: (json['recordingDurationSeconds'] as num?)?.toInt(),
      isTamperAttemptDetected: json['isTamperAttemptDetected'] as bool? ?? false,
      isWatchlistTarget: json['isWatchlistTarget'] as bool? ?? false,
    );
  }
}
