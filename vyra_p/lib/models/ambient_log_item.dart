class SpeakerVoiceProfile {
  final String speakerId;
  final String displayName;
  final bool isChild;
  final String pitch;
  final String tone;
  final String acousticDescription;

  const SpeakerVoiceProfile({
    required this.speakerId,
    required this.displayName,
    this.isChild = false,
    required this.pitch,
    required this.tone,
    required this.acousticDescription,
  });
}

class DialogueTurn {
  final String speakerId;
  final String speakerName;
  final String timestamp;
  final String hindiText;
  final String englishText;
  final String emotion;

  const DialogueTurn({
    required this.speakerId,
    required this.speakerName,
    required this.timestamp,
    required this.hindiText,
    required this.englishText,
    required this.emotion,
  });
}

class AmbientLogItem {
  final String id;
  final DateTime timestamp;
  final int durationSeconds;
  final String? audioUrl;
  final String locationContext;
  final String speechSnippet;
  final bool isFlagged;
  final String? detectedKeyword;
  final bool isPurgedFromCloud;
  final int storageFreedKb;
  final String conversationSummary;
  final List<SpeakerVoiceProfile> speakers;
  final List<DialogueTurn> dialogue;

  const AmbientLogItem({
    required this.id,
    required this.timestamp,
    required this.durationSeconds,
    this.audioUrl,
    required this.locationContext,
    required this.speechSnippet,
    this.isFlagged = false,
    this.detectedKeyword,
    this.isPurgedFromCloud = true,
    this.storageFreedKb = 3450, // Average 3.5 MB audio purged
    this.conversationSummary = '',
    this.speakers = const [],
    this.dialogue = const [],
  });

  String get formattedDuration {
    final mins = durationSeconds ~/ 60;
    final secs = durationSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  AmbientLogItem copyWith({
    bool? isPurgedFromCloud,
    int? storageFreedKb,
  }) {
    return AmbientLogItem(
      id: id,
      timestamp: timestamp,
      durationSeconds: durationSeconds,
      audioUrl: audioUrl,
      locationContext: locationContext,
      speechSnippet: speechSnippet,
      isFlagged: isFlagged,
      detectedKeyword: detectedKeyword,
      isPurgedFromCloud: isPurgedFromCloud ?? this.isPurgedFromCloud,
      storageFreedKb: storageFreedKb ?? this.storageFreedKb,
      conversationSummary: conversationSummary,
      speakers: speakers,
      dialogue: dialogue,
    );
  }
}
