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

      if (trimmedUrl.startsWith('http://') || trimmedUrl.startsWith('https://')) {
        await _player.play(UrlSource(trimmedUrl));
      } else if (trimmedUrl.startsWith('/')) {
        await _player.play(DeviceFileSource(trimmedUrl));
      } else {
        // Automatically resolve filename to Supabase recordings storage bucket
        final encodedUrl = Uri.encodeComponent(trimmedUrl).replaceAll('+', '%20');
        final supabaseAudioUrl = "https://wtlqlkkduescumpggttm.supabase.co/storage/v1/object/public/recordings/$encodedUrl";
        await _player.play(UrlSource(supabaseAudioUrl));
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
