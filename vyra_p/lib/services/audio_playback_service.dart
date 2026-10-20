import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AudioPlaybackService extends ChangeNotifier {
  static final AudioPlaybackService instance = AudioPlaybackService._internal();

  AudioPlaybackService._internal() {
    _init();
  }

  final AudioPlayer _player = AudioPlayer();
  String? _currentMediaId;
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _errorMessage;

  String? get currentMediaId => _currentMediaId;
  PlayerState get playerState => _playerState;
  bool get isPlaying => _playerState == PlayerState.playing;
  bool get isBuffering => _playerState == PlayerState.paused && _position == Duration.zero;
  Duration get position => _position;
  Duration get duration => _duration;
  String? get errorMessage => _errorMessage;

  void _init() {
    _player.onPlayerStateChanged.listen((state) {
      _playerState = state;
      if (state == PlayerState.completed) {
        _position = Duration.zero;
      }
      notifyListeners();
    });

    _player.onPositionChanged.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _player.onDurationChanged.listen((dur) {
      _duration = dur;
      notifyListeners();
    });
  }

  /// Normalizes and percent-encodes a recording URL or filename so Android ExoPlayer/MediaPlayer
  /// can stream files containing spaces, emojis, or special characters from Supabase Storage.
  static String normalizeAudioUrl(String rawUrl, {String defaultChildId = 'VYRA-13533'}) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('/')) return trimmed;

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      // 1. Google Drive direct byte-range acceleration:
      // Convert drive.google.com/uc?export=download&id=... or /file/d/... into direct content stream
      if (trimmed.contains('drive.google.com') || trimmed.contains('drive.usercontent.google.com')) {
        final idMatch = RegExp(r'(?:id=|\/d\/)([a-zA-Z0-9_-]+)').firstMatch(trimmed);
        if (idMatch != null) {
          final fileId = idMatch.group(1);
          return 'https://drive.usercontent.google.com/download?id=$fileId&export=download';
        }
      }

      const marker = '/storage/v1/object/public/recordings/';
      final idx = trimmed.indexOf(marker);
      if (idx != -1) {
        final baseUrl = trimmed.substring(0, idx + marker.length);
        final objectPath = trimmed.substring(idx + marker.length);
        final encodedSegments = objectPath.split('/').map((seg) {
          String decoded = seg;
          try {
            decoded = Uri.decodeComponent(seg);
          } catch (_) {}
          return Uri.encodeComponent(decoded).replaceAll('+', '%20');
        }).join('/');
        return '$baseUrl$encodedSegments';
      }
      try {
        return Uri.encodeFull(Uri.decodeFull(trimmed));
      } catch (_) {
        return Uri.encodeFull(trimmed);
      }
    }

    // Relative filename or childId/filename key
    String relativePath = trimmed;
    if (!relativePath.startsWith('VYRA-') && !relativePath.contains('/')) {
      relativePath = '$defaultChildId/$relativePath';
    }
    final encodedSegments = relativePath.split('/').map((seg) {
      String decoded = seg;
      try {
        decoded = Uri.decodeComponent(seg);
      } catch (_) {}
      return Uri.encodeComponent(decoded).replaceAll('+', '%20');
    }).join('/');

    return 'https://wtlqlkkduescumpggttm.supabase.co/storage/v1/object/public/recordings/$encodedSegments';
  }

  Future<void> play({
    required String mediaId,
    required String? url,
  }) async {
    _errorMessage = null;

    if (url == null || url.trim().isEmpty) {
      _errorMessage = "No remote audio file URL available.";
      notifyListeners();
      return;
    }

    final trimmedUrl = url.trim();

    // If tapping on currently playing track -> pause it
    if (_currentMediaId == mediaId && isPlaying) {
      await pause();
      return;
    }

    // If resuming currently paused track
    if (_currentMediaId == mediaId && _playerState == PlayerState.paused) {
      await _player.resume();
      return;
    }

    try {
      _currentMediaId = mediaId;
      _position = Duration.zero;
      _duration = Duration.zero;
      notifyListeners();

      if (trimmedUrl.startsWith('/')) {
        await _player.play(DeviceFileSource(trimmedUrl));
      } else {
        final resolvedUrl = normalizeAudioUrl(trimmedUrl);
        await _player.play(UrlSource(resolvedUrl));
      }
    } catch (e) {
      debugPrint("Audio playback error: $e");
      _errorMessage = "Playback failed: $e";
      _playerState = PlayerState.stopped;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      debugPrint("Audio pause error: $e");
    }
  }

  Future<void> resume() async {
    try {
      await _player.resume();
    } catch (e) {
      debugPrint("Audio resume error: $e");
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
      _currentMediaId = null;
      _position = Duration.zero;
      notifyListeners();
    } catch (e) {
      debugPrint("Audio stop error: $e");
    }
  }

  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } catch (e) {
      debugPrint("Audio seek error: $e");
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
