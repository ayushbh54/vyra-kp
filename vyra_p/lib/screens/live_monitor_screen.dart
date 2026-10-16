import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/parent_dashboard_provider.dart';
import '../services/lan_sync_service.dart';

enum LiveMonitorMode { screen, camera }

class LiveMonitorScreen extends StatefulWidget {
  final LiveMonitorMode initialMode;
  const LiveMonitorScreen({super.key, this.initialMode = LiveMonitorMode.camera});

  @override
  State<LiveMonitorScreen> createState() => _LiveMonitorScreenState();
}

class _LiveMonitorScreenState extends State<LiveMonitorScreen> {
  late LiveMonitorMode _currentMode;

  // ── Camera MJPEG state ───────────────────────────────────────────────────
  Uint8List? _currentFrame;
  Timer? _frameTimer;
  bool _isCameraConnecting = false;
  bool _isCameraActive = false;
  String? _cameraError;
  int _fps = 0;
  int _frameCount = 0;
  DateTime _fpsTimer = DateTime.now();

  // ── Live Audio state ─────────────────────────────────────────────────────
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAudioActive = false;
  bool _isAudioConnecting = false;
  String? _audioError;

  // ── LAN discovery ────────────────────────────────────────────────────────
  String? _childIp;
  final _lanService = LanSyncService();
  bool _isDiscovering = false;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;
    // Discover child IP on open
    WidgetsBinding.instance.addPostFrameCallback((_) => _discoverChild());
  }

  @override
  void dispose() {
    _stopCamera();
    _stopAudio();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ─────────────────────── LAN Discovery ───────────────────────────────────

  Future<void> _discoverChild() async {
    if (_isDiscovering) return;
    final provider = context.read<ParentDashboardProvider>();
    setState(() { _isDiscovering = true; _cameraError = null; _audioError = null; });
    try {
      final ip = await _lanService.discoverChildIp(
        pairingCode: provider.activePairingCode,
        knownIp: provider.childLanIp,
        timeout: const Duration(seconds: 5),
      );
      if (mounted) {
        setState(() { _childIp = ip; _isDiscovering = false; });
        if (ip != null) provider.setChildLanIp(ip);
      }
    } catch (e) {
      if (mounted) setState(() { _isDiscovering = false; });
    }
  }

  // ─────────────────────── Camera MJPEG ────────────────────────────────────

  Future<void> _startCamera() async {
    if (_childIp == null) {
      await _discoverChild();
      if (_childIp == null) {
        if (mounted) setState(() => _cameraError = 'Child not found on Wi-Fi. Same network par ho?');
        return;
      }
    }

    if (!mounted) return;
    final provider = context.read<ParentDashboardProvider>();
    setState(() { _isCameraConnecting = true; _cameraError = null; });

    provider.toggleRemoteCamera();
    await Future.delayed(const Duration(milliseconds: 800));

    _frameTimer?.cancel();
    _frameCount = 0;
    _fpsTimer = DateTime.now();

    if (mounted) setState(() { _isCameraConnecting = false; _isCameraActive = true; });

    final capturedIp = _childIp!;
    _frameTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!_isCameraActive) return;
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(milliseconds: 500);
        final request = await client.getUrl(
          Uri.parse('http://$capturedIp:8899/api/camera-frame'),
        );
        final response = await request.close().timeout(const Duration(milliseconds: 600));
        if (response.statusCode == 200) {
          // Collect response bytes manually
          final chunks = <int>[];
          await for (final chunk in response) { chunks.addAll(chunk); }
          final bytes = Uint8List.fromList(chunks);
          if (mounted && bytes.isNotEmpty) {
            _frameCount++;
            final now = DateTime.now();
            final diff = now.difference(_fpsTimer).inMilliseconds;
            if (diff >= 1000) {
              _fps = (_frameCount * 1000 / diff).round();
              _frameCount = 0;
              _fpsTimer = now;
            }
            setState(() { _currentFrame = bytes; _cameraError = null; });
          }
        } else if (response.statusCode == 503 && mounted) {
          setState(() => _cameraError = 'Camera not started on child. Retry karo.');
        }
        client.close(force: true);
      } catch (_) {
        // Ignore individual frame errors
      }
    });
  }

  void _stopCamera() {
    _frameTimer?.cancel();
    _frameTimer = null;
    if (_isCameraActive) {
      context.read<ParentDashboardProvider>().toggleRemoteCamera();
    }
    setState(() {
      _isCameraActive = false;
      _isCameraConnecting = false;
      _currentFrame = null;
      _fps = 0;
    });
  }

  // ─────────────────────── Live Audio ──────────────────────────────────────

  Future<void> _startAudio() async {
    if (_childIp == null) {
      await _discoverChild();
      if (_childIp == null) {
        setState(() => _audioError = 'Child not found on Wi-Fi.');
        return;
      }
    }
    if (!mounted) return;
    final provider = context.read<ParentDashboardProvider>();
    setState(() { _isAudioConnecting = true; _audioError = null; });

    // Send START_LIVE_AUDIO command to child
    provider.startLiveAudio();
    await Future.delayed(const Duration(milliseconds: 600)); // let AudioRecord start

    try {
      final url = 'http://$_childIp:8899/api/live-audio';
      await _audioPlayer.setSourceUrl(url);
      await _audioPlayer.resume();
      if (mounted) setState(() { _isAudioActive = true; _isAudioConnecting = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAudioConnecting = false;
          _audioError = 'Audio connect failed: $e';
        });
        provider.stopLiveAudio();
      }
    }
  }

  Future<void> _stopAudio() async {
    await _audioPlayer.stop();
    if (mounted) {
      context.read<ParentDashboardProvider>().stopLiveAudio();
      setState(() { _isAudioActive = false; _isAudioConnecting = false; });
    }
  }

  // ─────────────────────────── UI ──────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ParentDashboardProvider>();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.85),
        elevation: 0,
        title: Text(
          _currentMode == LiveMonitorMode.camera ? '📷 Live Camera' : '🖥️ Live Screen',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          // Rediscover child IP
          IconButton(
            icon: _isDiscovering
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.wifi_find, color: Colors.white),
            tooltip: 'Find child on Wi-Fi',
            onPressed: _discoverChild,
          ),
          // Switch mode
          IconButton(
            icon: Icon(
              _currentMode == LiveMonitorMode.camera ? Icons.screen_share : Icons.videocam,
              color: Colors.white70,
            ),
            tooltip: 'Switch mode',
            onPressed: () {
              _stopCamera();
              setState(() {
                _currentMode = _currentMode == LiveMonitorMode.camera
                    ? LiveMonitorMode.screen
                    : LiveMonitorMode.camera;
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Main video/camera area ────────────────────────────────────────
          _buildVideoArea(provider),

          // ── Status bar top-left ───────────────────────────────────────────
          _buildStatusBar(),

          // ── Child IP chip top-right ───────────────────────────────────────
          _buildIpChip(),

          // ── Error banner ──────────────────────────────────────────────────
          if (_cameraError != null || _audioError != null) _buildErrorBanner(),

          // ── Bottom controls ───────────────────────────────────────────────
          Positioned(
            bottom: 24, left: 16, right: 16,
            child: _buildControlBar(provider),
          ),
        ],
      ),
    );
  }

  // ── Main video area ───────────────────────────────────────────────────────

  Widget _buildVideoArea(ParentDashboardProvider provider) {
    if (_isCameraConnecting || _isAudioConnecting || _isDiscovering) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(color: Color(0xFF38BDF8)),
          const SizedBox(height: 16),
          Text(
            _isDiscovering ? 'Child ko Wi-Fi par dhundh raha hai...'
                : _isCameraConnecting ? 'Camera connect ho raha hai...'
                : 'Audio connect ho raha hai...',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ]),
      );
    }

    if (_isCameraActive && _currentFrame != null) {
      // Live MJPEG frames from child Camera2
      return Center(
        child: Image.memory(
          _currentFrame!,
          gaplessPlayback: true,      // no flicker between frames
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }

    // Idle / not started state
    return Center(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFF0F172A),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(
            _currentMode == LiveMonitorMode.camera ? Icons.videocam_off : Icons.screen_share,
            size: 72, color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
          ),
          const SizedBox(height: 20),
          Text(
            _childIp != null
                ? 'Child found: $_childIp\nNeeche camera button dabao'
                : 'Child ko same Wi-Fi par connect karo\nPhir 📡 button dabao',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.6),
          ),
          if (_childIp != null) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0EA5E9),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              icon: const Icon(Icons.videocam, color: Colors.white),
              label: const Text('Live Camera Start Karo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: _startCamera,
            ),
          ],
        ]),
      ),
    );
  }

  // ── Status bar (LIVE badge + FPS) ─────────────────────────────────────────

  Widget _buildStatusBar() {
    return Positioned(
      top: 12, left: 12,
      child: Row(children: [
        if (_isCameraActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const CircleAvatar(radius: 4, backgroundColor: Colors.white),
              const SizedBox(width: 6),
              Text('LIVE${_fps > 0 ? " $_fps FPS" : ""}',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ]),
          ),
        if (_isAudioActive) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.mic, color: Colors.white, size: 12),
              SizedBox(width: 4),
              Text('LIVE AUDIO', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Child IP chip ─────────────────────────────────────────────────────────

  Widget _buildIpChip() {
    return Positioned(
      top: 12, right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          _childIp != null ? '📡 $_childIp' : '📡 Searching...',
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ),
    );
  }

  // ── Error banner ──────────────────────────────────────────────────────────

  Widget _buildErrorBanner() {
    return Positioned(
      bottom: 110, left: 16, right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF7F1D1D).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _cameraError ?? _audioError ?? '',
          style: const TextStyle(color: Colors.white, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ── Bottom control bar ────────────────────────────────────────────────────

  Widget _buildControlBar(ParentDashboardProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [

        // ── LIVE AUDIO (one-tap) ──────────────────────────────────────────
        _ControlButton(
          icon: _isAudioActive ? Icons.hearing : Icons.hearing_disabled,
          label: _isAudioActive ? 'Stop Audio' : 'Live Suno',
          color: _isAudioActive ? const Color(0xFF16A34A) : Colors.white70,
          isLoading: _isAudioConnecting,
          onTap: _isAudioActive ? _stopAudio : _startAudio,
        ),

        // ── CAMERA ON/OFF ─────────────────────────────────────────────────
        _ControlButton(
          icon: _isCameraActive ? Icons.videocam_off : Icons.videocam,
          label: _isCameraActive ? 'Camera Band' : 'Camera On',
          color: _isCameraActive ? Colors.redAccent : const Color(0xFF0EA5E9),
          isLoading: _isCameraConnecting,
          onTap: _isCameraActive ? _stopCamera : _startCamera,
        ),

        // ── FLIP LENS ─────────────────────────────────────────────────────
        _ControlButton(
          icon: Icons.flip_camera_android,
          label: provider.currentCameraLens == 'back' ? 'Front' : 'Back',
          color: Colors.white70,
          onTap: () {
            provider.switchCameraLens();
            if (_isCameraActive) {
              // Restart camera feed with new lens
              _stopCamera();
              Future.delayed(const Duration(milliseconds: 500), _startCamera);
            }
          },
        ),

        // ── TORCH ────────────────────────────────────────────────────────
        _ControlButton(
          icon: provider.isFlashlightOn ? Icons.flash_on : Icons.flash_off,
          label: provider.isFlashlightOn ? 'Flash Off' : 'Flash On',
          color: provider.isFlashlightOn ? Colors.amber : Colors.white70,
          onTap: provider.toggleFlashlight,
        ),

        // ── CLOSE ─────────────────────────────────────────────────────────
        _ControlButton(
          icon: Icons.close,
          label: 'Band Karo',
          color: Colors.redAccent,
          onTap: () {
            _stopCamera();
            _stopAudio();
            Navigator.pop(context);
          },
        ),
      ]),
    );
  }
}

// ─────────────────────────── Helper widget ───────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool isLoading;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        isLoading
            ? SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(color: color, strokeWidth: 2.5))
            : Icon(icon, color: color, size: 26),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
