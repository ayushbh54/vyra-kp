class AmbientLogItem {
  final String id;
  final DateTime timestamp;
  final int durationSeconds;
  final String? audioUrl;
  final String locationContext;
  final String speechSnippet;
  final bool isFlagged;
  final String? detectedKeyword;

  const AmbientLogItem({
    required this.id,
    required this.timestamp,
    required this.durationSeconds,
    this.audioUrl,
    required this.locationContext,
    required this.speechSnippet,
    this.isFlagged = false,
    this.detectedKeyword,
  });

  String get formattedDuration {
    final mins = durationSeconds ~/ 60;
    final secs = durationSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
