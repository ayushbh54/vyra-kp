import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/parent_dashboard_provider.dart';

enum LiveMonitorMode { screen, camera }

class LiveMonitorScreen extends StatefulWidget {
  final LiveMonitorMode initialMode;

  const LiveMonitorScreen({super.key, this.initialMode = LiveMonitorMode.screen});

  @override
  State<LiveMonitorScreen> createState() => _LiveMonitorScreenState();
}

class _LiveMonitorScreenState extends State<LiveMonitorScreen> {
  late LiveMonitorMode _currentMode;
  bool _isAudioEnabled = true;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ParentDashboardProvider>();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        elevation: 0,
        title: Text(
          _currentMode == LiveMonitorMode.screen ? 'Live Screen Mirror' : 'Remote Camera Feed',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _currentMode == LiveMonitorMode.screen ? Icons.videocam : Icons.screen_share,
              color: Colors.white,
            ),
            tooltip: 'Switch Mode',
            onPressed: () {
              setState(() {
                _currentMode = (_currentMode == LiveMonitorMode.screen)
                    ? LiveMonitorMode.camera
                    : LiveMonitorMode.screen;
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Video Player Simulation Container
          Center(
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: const Color(0xFF0F172A),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _currentMode == LiveMonitorMode.screen ? Icons.phone_android : Icons.camera_alt,
                    size: 80,
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _currentMode == LiveMonitorMode.screen
                        ? 'Live Screen Stream Active (WebRTC 1080p)'
                        : 'Remote Camera Active (${provider.currentCameraLens.toUpperCase()} LENS)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Streaming from ${provider.activeChild.deviceModel} • 60 FPS Ultra-HD • 48 kHz Opus Studio • 85ms Latency',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),

          // Top Status Bar Overlay
          Positioned(
            top: 16,
            left: 16,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(radius: 4, backgroundColor: Colors.white),
                      SizedBox(width: 6),
                      Text('LIVE 60 FPS', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text('1080p FHD', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),

          // Bottom Controls Floating Bar
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Switch Lens (Only for Camera mode)
                  if (_currentMode == LiveMonitorMode.camera)
                    IconButton(
                      icon: const Icon(Icons.flip_camera_android, color: Colors.white),
                      tooltip: 'Flip Lens',
                      onPressed: () {
                        provider.switchCameraLens();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Switched to ${provider.currentCameraLens.toUpperCase()} camera'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                    ),

                  // Flashlight (Only for Camera mode)
                  if (_currentMode == LiveMonitorMode.camera)
                    IconButton(
                      icon: Icon(
                        provider.isFlashlightOn ? Icons.flash_on : Icons.flash_off,
                        color: provider.isFlashlightOn ? Colors.amber : Colors.white,
                      ),
                      tooltip: 'Flashlight',
                      onPressed: () => provider.toggleFlashlight(),
                    ),

                  // Stealth Guard (Auto-Kill on Screen Wake to avoid Green Dot)
                  IconButton(
                    icon: Icon(
                      provider.isStealthScreenGuardEnabled ? Icons.shield : Icons.shield_outlined,
                      color: provider.isStealthScreenGuardEnabled ? const Color(0xFF10B981) : Colors.grey,
                    ),
                    tooltip: 'Stealth Guard: Auto-Cut on Screen Wake',
                    onPressed: () {
                      provider.toggleStealthScreenGuard();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            provider.isStealthScreenGuardEnabled
                                ? '🛡️ Stealth Guard ON: Camera/Mic will auto-cut if child wakes screen (Bypasses Green Dot)'
                                : '⚠️ Stealth Guard OFF: Continuous streaming even if screen wakes',
                          ),
                          backgroundColor: provider.isStealthScreenGuardEnabled ? const Color(0xFF065F46) : const Color(0xFF7F1D1D),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),

                  // Audio Mute/Unmute
                  IconButton(
                    icon: Icon(
                      _isAudioEnabled ? Icons.volume_up : Icons.volume_off,
                      color: _isAudioEnabled ? const Color(0xFF10B981) : Colors.white,
                    ),
                    tooltip: 'Ambient Sound',
                    onPressed: () {
                      setState(() => _isAudioEnabled = !_isAudioEnabled);
                    },
                  ),

                  // Snapshot / Photo Capture
                  IconButton(
                    icon: const Icon(Icons.camera, color: Color(0xFF38BDF8), size: 28),
                    tooltip: 'Capture Snapshot',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Snapshot saved to Parent Gallery!'),
                          backgroundColor: Color(0xFF10B981),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),

                  // Close Button
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.redAccent),
                    tooltip: 'Stop Stream',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
