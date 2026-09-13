import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/parent_dashboard_provider.dart';
import '../widgets/quick_action_tile.dart';
import '../widgets/voice_intercom_sheet.dart';
import 'live_monitor_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ParentDashboardProvider>();
    final activeChild = provider.activeChild;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF10B981)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'V',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vyra Parent',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Active: ${activeChild.name} (${activeChild.deviceModel})',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: activeChild.isOnline
                  ? const Color(0xFF10B981).withValues(alpha: 0.2)
                  : Colors.red.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: activeChild.isOnline ? const Color(0xFF10B981) : Colors.red,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 4,
                  backgroundColor: activeChild.isOnline ? const Color(0xFF10B981) : Colors.red,
                ),
                const SizedBox(width: 6),
                Text(
                  activeChild.isOnline ? 'LIVE' : 'OFFLINE',
                  style: TextStyle(
                    color: activeChild.isOnline ? const Color(0xFF10B981) : Colors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 👨‍👩‍👧‍👦 Multi-Child Switcher Bar
            const Text(
              'Select Child Profile',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: provider.children.map((child) {
                  final isSelected = child.id == provider.activeChildId;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      onTap: () => provider.switchChild(child.id),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF1E88E5).withValues(alpha: 0.2) : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF1E88E5) : const Color(0xFF334155),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: isSelected ? const Color(0xFF1E88E5) : const Color(0xFF475569),
                              child: Text(
                                child.name[0],
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      child.name,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    CircleAvatar(
                                      radius: 3.5,
                                      backgroundColor: child.isOnline ? const Color(0xFF10B981) : Colors.red,
                                    ),
                                  ],
                                ),
                                Text(
                                  '${child.deviceModel} • ${child.batteryLevel}%',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 20),

            // Active Device Status Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activeChild.deviceModel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Disguise: ${activeChild.selectedDisguise} • Android 14',
                            style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.battery_5_bar, color: Color(0xFF10B981), size: 18),
                            const SizedBox(width: 4),
                            Text(
                              '${activeChild.batteryLevel}%',
                              style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFF334155), height: 1),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Color(0xFF38BDF8), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          activeChild.locationAddress,
                          style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text(
              'Real-Time Controls',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Quick Actions: Row 1
            Row(
              children: [
                QuickActionTile(
                  icon: Icons.screen_share,
                  label: 'Live Screen',
                  sublabel: 'Mirror Display',
                  color: const Color(0xFF3B82F6),
                  isActive: provider.isLiveScreenActive,
                  onTap: () {
                    provider.toggleLiveScreen();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LiveMonitorScreen(initialMode: LiveMonitorMode.screen),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                QuickActionTile(
                  icon: Icons.videocam,
                  label: 'Remote Cam',
                  sublabel: 'Front / Back',
                  color: const Color(0xFF10B981),
                  isActive: provider.isRemoteCameraActive,
                  onTap: () {
                    provider.toggleRemoteCamera();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LiveMonitorScreen(initialMode: LiveMonitorMode.camera),
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Quick Actions: Row 2 (🎙️ Voice Intercom & 🔒 Lock Phone)
            Row(
              children: [
                QuickActionTile(
                  icon: Icons.record_voice_over,
                  label: 'Voice Intercom',
                  sublabel: 'Speaker Blast',
                  color: const Color(0xFF06B6D4),
                  isActive: false,
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => const VoiceIntercomSheet(),
                    );
                  },
                ),
                const SizedBox(width: 12),
                QuickActionTile(
                  icon: provider.isPhoneLocked ? Icons.lock : Icons.lock_open,
                  label: provider.isPhoneLocked ? 'Locked' : 'Lock Phone',
                  sublabel: provider.isPhoneLocked ? 'Emergency Lock' : 'Restricts Usage',
                  color: provider.isPhoneLocked ? Colors.redAccent : const Color(0xFFA855F7),
                  isActive: provider.isPhoneLocked,
                  onTap: () {
                    provider.toggleLockPhone();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          provider.isPhoneLocked
                              ? 'Emergency Lock command sent to ${activeChild.name}\'s phone.'
                              : '${activeChild.name}\'s phone unlocked.',
                        ),
                        backgroundColor: provider.isPhoneLocked ? Colors.redAccent : const Color(0xFF10B981),
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 28),
            const Text(
              'Critical Safety Alerts',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Alert 1: Anti-Tamper Triggered
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.shade700, width: 1),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: Colors.amber, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Call Recording Tamper Blocked',
                          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Child tapped "Stop Recording" during active call. Vyra auto-resumed recording and saved audio.',
                          style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Alert 2: Deleted Message Captured
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.blue.shade700, width: 1),
              ),
              child: const Row(
                children: [
                  Icon(Icons.history_toggle_off, color: Colors.lightBlueAccent, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WhatsApp Deleted Message Preserved',
                          style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Unknown sender used "Delete for Everyone". Full text safely archived in your Chats feed.',
                          style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
