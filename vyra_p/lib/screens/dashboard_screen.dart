import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/parent_dashboard_provider.dart';
import '../models/child_profile.dart';
import '../widgets/quick_action_tile.dart';
import '../widgets/voice_intercom_sheet.dart';
import 'live_monitor_screen.dart';
import 'ambient_logs_screen.dart';

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
          IconButton(
            icon: const Icon(Icons.security, color: Color(0xFF38BDF8), size: 22),
            tooltip: 'Safety & Emergency Controls',
            onPressed: () => _showSafetySettingsSheet(context, provider),
          ),
          const SizedBox(width: 8),
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
                children: [
                  ...provider.children.map((child) {
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
                  }),
                  // ➕ Add New Child Button
                  InkWell(
                    onTap: () => _showAddChildDialog(context, provider),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                            child: const Icon(Icons.add, color: Color(0xFF38BDF8), size: 16),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '+ Add Child',
                            style: TextStyle(
                              color: Color(0xFF38BDF8),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 🔑 Family Pairing Code Banner
            Container(
              margin: const EdgeInsets.only(top: 14, bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E3A8A), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.qr_code_scanner, color: Color(0xFF38BDF8), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CHILD PAIRING CODE',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          provider.activePairingCode,
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showPairingSheet(context, provider),
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('Pair Device', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 📶 Same-Wi-Fi Direct LAN Sync Card (Zero Cloud Quotas)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: provider.isLanSyncActive
                      ? [const Color(0xFF064E3B), const Color(0xFF0F172A)]
                      : [const Color(0xFF1E293B), const Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: provider.isLanSyncActive
                      ? const Color(0xFF10B981).withValues(alpha: 0.6)
                      : const Color(0xFF334155),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: provider.isLanSyncActive
                          ? const Color(0xFF10B981).withValues(alpha: 0.2)
                          : const Color(0xFF64748B).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.wifi_rounded,
                      color: provider.isLanSyncActive
                          ? const Color(0xFF10B981)
                          : const Color(0xFF94A3B8),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.isLanSyncActive
                              ? '🟢 SAME WI-FI DIRECT SYNC ACTIVE'
                              : '📶 SAME WI-FI AUTO-SYNC',
                          style: TextStyle(
                            color: provider.isLanSyncActive
                                ? const Color(0xFF34D399)
                                : const Color(0xFF94A3B8),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          provider.isLanSyncActive
                              ? 'Connected to ${provider.lanChildIp ?? "Child"} (Zero Cloud Quota)'
                              : 'Detects child on same Wi-Fi for zero-quota sync',
                          style: TextStyle(
                            color: provider.isLanSyncActive ? Colors.white : const Color(0xFFCBD5E1),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: provider.isLanSyncing
                        ? null
                        : () async {
                            final ok = await provider.triggerLanSync(showFeedback: true);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok
                                      ? '✅ Direct Wi-Fi sync completed! All data updated.'
                                      : '⚠️ Child device not detected on current Wi-Fi yet. Checking cloud...'),
                                  backgroundColor: ok ? const Color(0xFF059669) : const Color(0xFFD97706),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                    icon: provider.isLanSyncing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                          )
                        : Icon(
                            provider.isLanSyncActive ? Icons.sync : Icons.radar,
                            size: 16,
                            color: provider.isLanSyncActive ? const Color(0xFF34D399) : const Color(0xFF38BDF8),
                          ),
                    label: Text(
                      provider.isLanSyncing
                          ? 'Syncing...'
                          : (provider.isLanSyncActive ? 'Sync Now' : 'Find Wi-Fi'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: provider.isLanSyncActive ? const Color(0xFF34D399) : const Color(0xFF38BDF8),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ☁️ Supabase Cloud Archive & Real-Time Sync Status Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F2E23), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF34D399),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '✅ SUPABASE CLOUD ARCHIVE & SYNC',
                              style: TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '100% Supabase Cloud-Synced • Real-Time Archive',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // ── Refresh button with last-sync time ────────────────
                      GestureDetector(
                        onTap: provider.isSupabaseSyncing
                            ? null
                            : () => provider.refreshAll(forceFull: true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: provider.isSupabaseSyncing
                                  ? const Color(0xFF34D399).withValues(alpha: 0.4)
                                  : const Color(0xFF34D399).withValues(alpha: 0.7),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              provider.isSupabaseSyncing
                                  ? const SizedBox(
                                      width: 12, height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Color(0xFF34D399)))
                                  : const Icon(Icons.refresh_rounded,
                                      size: 14, color: Color(0xFF34D399)),
                              const SizedBox(width: 5),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    provider.isSupabaseSyncing ? 'Sync ho raha...' : 'Refresh Karo',
                                    style: const TextStyle(
                                      fontSize: 11, fontWeight: FontWeight.bold,
                                      color: Color(0xFF34D399),
                                    ),
                                  ),
                                  Text(
                                    provider.lastSyncedLabel,
                                    style: TextStyle(
                                      fontSize: 9, color: Colors.white.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text(
                          '💬 ${provider.totalChatsCount} Chats',
                          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        Container(width: 1, height: 12, color: const Color(0xFF475569)),
                        Text(
                          '📞 ${provider.totalCallsCount} Calls',
                          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        Container(width: 1, height: 12, color: const Color(0xFF475569)),
                        Text(
                          '🔔 ${provider.totalNotifsCount} Notifs',
                          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        Container(width: 1, height: 12, color: const Color(0xFF475569)),
                        const Text(
                          '🟢 Supabase Active',
                          style: TextStyle(
                            color: Color(0xFF34D399),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

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
                          InkWell(
                            onTap: () => _showDisguisePickerSheet(context, provider),
                            borderRadius: BorderRadius.circular(6),
                            child: Row(
                              children: [
                                Text(
                                  'Icon: ${activeChild.selectedDisguise}',
                                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.edit, color: Color(0xFF38BDF8), size: 12),
                                const Text(
                                  ' • Android 14',
                                  style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                ),
                              ],
                            ),
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

            const SizedBox(height: 18),

            // 📊 Daily Screen Time & Digital Wellbeing Card
            _buildScreenTimeCard(context, provider),

            const SizedBox(height: 18),

            // 🛡️ Stealth Security Guard Card (Green Dot Bypass Toggle)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: provider.isStealthScreenGuardEnabled
                    ? const Color(0xFF064E3B).withValues(alpha: 0.4)
                    : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: provider.isStealthScreenGuardEnabled
                      ? const Color(0xFF10B981)
                      : const Color(0xFF334155),
                  width: provider.isStealthScreenGuardEnabled ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: provider.isStealthScreenGuardEnabled
                          ? const Color(0xFF10B981).withValues(alpha: 0.2)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      provider.isStealthScreenGuardEnabled
                          ? Icons.shield
                          : Icons.shield_outlined,
                      color: provider.isStealthScreenGuardEnabled
                          ? const Color(0xFF10B981)
                          : Colors.grey,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              provider.isStealthScreenGuardEnabled
                                  ? 'Stealth Guard: ON'
                                  : 'Stealth Guard: OFF',
                              style: TextStyle(
                                color: provider.isStealthScreenGuardEnabled
                                    ? const Color(0xFF34D399)
                                    : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: provider.isStealthScreenGuardEnabled
                                    ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                    : Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                provider.isStealthScreenGuardEnabled ? 'BYPASS DOT' : 'CONTINUOUS',
                                style: TextStyle(
                                  color: provider.isStealthScreenGuardEnabled
                                      ? const Color(0xFF10B981)
                                      : Colors.orange,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          provider.isStealthScreenGuardEnabled
                              ? 'Screen-off stealth: auto-cuts mic/cam on screen wake so child never spots green dot.'
                              : 'Normal mode: camera & mic keep streaming continuously without auto-cut.',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: provider.isStealthScreenGuardEnabled,
                    activeThumbColor: const Color(0xFF10B981),
                    activeTrackColor: const Color(0xFF065F46),
                    inactiveThumbColor: Colors.grey,
                    inactiveTrackColor: const Color(0xFF334155),
                    onChanged: (_) => provider.toggleStealthScreenGuard(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Quick Actions Section Header
            const Text(
              'Quick Remote Actions',
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
                  sublabel: provider.isPhoneLocked ? 'Tap to Unlock' : 'Restricts Usage',
                  color: provider.isPhoneLocked ? Colors.redAccent : const Color(0xFFA855F7),
                  isActive: provider.isPhoneLocked,
                  onTap: () {
                    if (!provider.isPhoneLocked) {
                      _showSafeLockDialog(context, provider, activeChild);
                    } else {
                      provider.toggleLockPhone();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${activeChild.name}\'s phone unlocked. Full access restored.'),
                          backgroundColor: const Color(0xFF10B981),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),

            const SizedBox(height: 14),

            // 🎨 1-Click App Icon & Name Changer Banner
            InkWell(
              onTap: () => _showDisguisePickerSheet(context, provider),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.palette_outlined, color: Color(0xFF38BDF8), size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '1-Click App Icon & Name Changer',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Active: ${activeChild.selectedDisguise} • Tap to switch icon remotely',
                            style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Text('Change', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward_ios, color: Color(0xFF38BDF8), size: 10),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ☁️ Cloud Storage Purge & Free Space Button
            InkWell(
              onTap: () => _showCloudPurgeDialog(context, provider),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.cloud_sync_outlined, color: Color(0xFF10B981), size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Supabase Cloud Cleanup (Free Space)',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Purge cloud records • Phone local history remains safe',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Text('Clean', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                          SizedBox(width: 4),
                          Icon(Icons.cleaning_services_outlined, color: Color(0xFF10B981), size: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // 🎙️ Ambient Voice Logs Banner
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AmbientLogsScreen()),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.graphic_eq, color: Color(0xFF38BDF8), size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Ambient Voice Logs',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${provider.ambientLogs.length} SESSIONS',
                                  style: const TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Review what was spoken around child while phone was in pocket.',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
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

  Widget _buildScreenTimeCard(BuildContext context, ParentDashboardProvider provider) {
    final totalMinutes = provider.todayScreenTimeMinutes;
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    final timeStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';
    final apps = provider.todayAppUsages;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hourglass_top_rounded, color: Color(0xFF38BDF8), size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Daily Screen Time & App Usage',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Official Android UsageStatsManager API',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 10),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4)),
                ),
                child: Text(
                  totalMinutes > 0 ? timeStr : '0m Today',
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (apps.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: Color(0xFF334155), height: 1),
            const SizedBox(height: 12),
            ...apps.take(4).map((app) {
              final appMins = app['minutes'] as int? ?? 0;
              final appHours = appMins ~/ 60;
              final appRemMins = appMins % 60;
              final appTimeStr = appHours > 0 ? '${appHours}h ${appRemMins}m' : '${appRemMins}m';
              final progress = totalMinutes > 0 ? (appMins / totalMinutes).clamp(0.0, 1.0) : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            app['appName'] ?? 'App',
                            style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          appTimeStr,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: const Color(0xFF0F172A),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ] else ...[
            const SizedBox(height: 10),
            const Text(
              'No app usage recorded today yet or permission pending on child device.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  void _showSafeLockDialog(BuildContext context, ParentDashboardProvider provider, ChildProfile child) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_outlined, color: Colors.amber, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Safety Verification',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to lock ${child.name}\'s phone?',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 16),
                      SizedBox(width: 6),
                      Text(
                        'EMERGENCY PROTECTION ACTIVE',
                        style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    '• Emergency SOS (112, 100, Police) is NEVER blocked.\n'
                    '• Child can call Parents with 1 emergency tap.\n'
                    '• Only games, social apps & browser are restricted.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel / Keep Safe', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              provider.toggleLockPhone();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Restricted mode sent to ${child.name}\'s phone. Emergency SOS remains open.'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            },
            child: const Text('Confirm Lock', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSafetySettingsSheet(BuildContext context, ParentDashboardProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateSheet) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.security, color: Color(0xFF38BDF8), size: 22),
                          ),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Safety & Emergency Controls',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Granular safeguards & emergency configuration',
                                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Emergency Whitelist Status
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF064E3B).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.health_and_safety_rounded, color: Color(0xFF10B981), size: 24),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Emergency SOS Immune from All Locks',
                                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '112, 100, Police, Ambulance & Parent Contacts will never be blocked under any circumstance.',
                                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Control 1: Geo-Fence Toggle (Default OFF)
                  _ControlSwitchTile(
                    title: 'Geo-Fence Boundary Monitoring',
                    subtitle: provider.isGeofenceEnabled
                        ? 'Active: Alerts if child exits designated safe area'
                        : 'OFF (Recommended Default): No automated lock or restriction while moving',
                    value: provider.isGeofenceEnabled,
                    icon: Icons.share_location_rounded,
                    activeTrackColor: const Color(0xFF38BDF8),
                    onChanged: (val) {
                      provider.toggleGeofence();
                      setStateSheet(() {});
                    },
                  ),

                  const SizedBox(height: 12),

                  // Control 2: Stealth Security Guard
                  _ControlSwitchTile(
                    title: 'Stealth Guard (Screen-On Auto-Cut)',
                    subtitle: 'Cuts camera and mic instantly when child wakes screen to prevent green dot visibility',
                    value: provider.isStealthScreenGuardEnabled,
                    icon: Icons.remove_red_eye_outlined,
                    activeTrackColor: const Color(0xFF10B981),
                    onChanged: (val) {
                      provider.toggleStealthScreenGuard();
                      setStateSheet(() {});
                    },
                  ),

                  const SizedBox(height: 12),

                  // Control 3: Cloud Auto-Purge
                  _ControlSwitchTile(
                    title: 'Cloud Storage Auto-Purge',
                    subtitle: 'Wipes heavy raw audio from cloud disk after sync; preserves dialogue transcripts (0 MB bloat)',
                    value: provider.autoPurgeCloudStorage,
                    icon: Icons.cleaning_services_rounded,
                    activeTrackColor: const Color(0xFF0284C7),
                    onChanged: (val) {
                      provider.toggleAutoPurgeCloudStorage();
                      setStateSheet(() {});
                    },
                  ),

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Save & Close Controls', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showDisguisePickerSheet(BuildContext context, ParentDashboardProvider provider) {
    final currentDisguise = provider.activeChild.selectedDisguise;

    final options = [
      {
        'title': 'System Sync',
        'subtitle': 'Google account cloud synchronization (Purple Sync Icon)',
        'icon': Icons.sync,
        'color': const Color(0xFF8B5CF6),
      },
      {
        'title': 'Google Services',
        'subtitle': 'Google Play & Core Android system services',
        'icon': Icons.sync,
        'color': const Color(0xFF8B5CF6),
      },
      {
        'title': 'System Toolkit',
        'subtitle': 'Default system utility found on all Android phones',
        'icon': Icons.build_circle_outlined,
        'color': const Color(0xFF38BDF8),
      },
      {
        'title': 'Device Support',
        'subtitle': 'Hardware diagnostics & phone maintenance',
        'icon': Icons.build_circle_outlined,
        'color': const Color(0xFF10B981),
      },
      {
        'title': 'Digital Compass',
        'subtitle': 'Sensor utility with real heading display',
        'icon': Icons.explore,
        'color': const Color(0xFFF59E0B),
      },
      {
        'title': 'Invisible Ghost',
        'subtitle': 'Vanishes 100% from App Drawer & Home Screen',
        'icon': Icons.visibility_off,
        'color': const Color(0xFFEC4899),
      },
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF475569),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.palette_outlined, color: Color(0xFF38BDF8), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '1-Click App Icon & Name Changer',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Tap any disguise to apply instantly on child\'s phone',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ...options.map((opt) {
                final isSelected = opt['title'] == currentDisguise;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () {
                      provider.switchDisguise(opt['title'] as String);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('App icon & name changed to "${opt['title']}"!'),
                          backgroundColor: const Color(0xFF0F172A),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (opt['color'] as Color).withValues(alpha: 0.15)
                            : const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? (opt['color'] as Color) : const Color(0xFF334155),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (opt['color'] as Color).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(opt['icon'] as IconData, color: opt['color'] as Color, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  opt['title'] as String,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
                                    fontSize: 14,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  opt['subtitle'] as String,
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20)
                          else
                            const Icon(Icons.arrow_forward_ios, color: Color(0xFF64748B), size: 14),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showPairingSheet(BuildContext context, ParentDashboardProvider provider) {
    final textController = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.qr_code_2, color: Color(0xFF38BDF8), size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Link Child Device',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Enter this pairing code on child phone',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Code Display Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
                ),
                child: Column(
                  children: [
                    const Text(
                      'ACTIVE PAIRING CODE',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      provider.activePairingCode,
                      style: const TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: provider.activePairingCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Pairing code copied to clipboard!'),
                            backgroundColor: Color(0xFF10B981),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy Code'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF334155),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 3-Step Setup Instructions
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '3-Step Quick Setup on Child Device:',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 6),
                    Text('1. Install Kid APK (System Toolkit) on child phone.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                    Text('2. In Step 1, enter the code shown above.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                    Text('3. Allow permissions and tap Complete Setup & Activate.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Connect Different / Existing Code
              const Text(
                'Already used a different code in Kid App?',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: textController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'e.g. VYRA-8921 or child_1',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () {
                      final input = textController.text.trim();
                      if (input.isNotEmpty) {
                        provider.linkChildWithCode(input);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Linked to device code: $input'),
                            backgroundColor: const Color(0xFF10B981),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Link', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddChildDialog(BuildContext context, ParentDashboardProvider provider) {
    final nameController = TextEditingController();
    final modelController = TextEditingController();
    final codeController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_add_alt_1, color: Color(0xFF38BDF8), size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Child Profile',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Isolates calls, chats, logs & location',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'CHILD NAME',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Aryan, Ananya, Kabir',
                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF38BDF8), size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'DEVICE MODEL (OPTIONAL)',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: modelController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Samsung Galaxy M32, OnePlus Nord',
                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  prefixIcon: const Icon(Icons.phone_android, color: Color(0xFF94A3B8), size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'CUSTOM PAIRING CODE (OPTIONAL)',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: codeController,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 1.5, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'Leave empty for auto-generated (e.g. VYRA-XXXX)',
                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12, letterSpacing: 0),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  prefixIcon: const Icon(Icons.vpn_key_outlined, color: Color(0xFF10B981), size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a name for the child'),
                          backgroundColor: Color(0xFFEF4444),
                        ),
                      );
                      return;
                    }

                    final model = modelController.text.trim();
                    final code = codeController.text.trim();
                    final newProfile = provider.addNewChild(
                      name: name,
                      deviceModel: model.isNotEmpty ? model : null,
                      customCode: code.isNotEmpty ? code : null,
                    );

                    Navigator.pop(ctx);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Added ${newProfile.name}! Pairing Code: ${newProfile.pairingCode}'),
                        backgroundColor: const Color(0xFF10B981),
                      ),
                    );

                    // Immediately open the pairing sheet showing the code
                    _showPairingSheet(context, provider);
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text('Add & View Pairing Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCloudPurgeDialog(BuildContext context, ParentDashboardProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.cleaning_services_rounded, color: Color(0xFF10B981)),
            SizedBox(width: 10),
            Text('Free Cloud Space', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: const Text(
          'Do you want to purge older records from Supabase Cloud to free up storage space?\n\n'
          '✅ All messages and calls currently saved on your phone will remain 100% safe in local storage.',
          style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await provider.purgeSupabaseCloudStorage();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? '✅ Cloud storage cleared successfully! Local records preserved.'
                        : '⚠️ Could not reach Supabase cloud. Check internet connection.'),
                    backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                );
              }
            },
            child: const Text('Clear Cloud Data'),
          ),
        ],
      ),
    );
  }
}

class _ControlSwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final IconData icon;
  final Color activeTrackColor;
  final ValueChanged<bool> onChanged;

  const _ControlSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.icon,
    required this.activeTrackColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value ? activeTrackColor.withValues(alpha: 0.2) : const Color(0xFF334155),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: value ? activeTrackColor : const Color(0xFF94A3B8), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, height: 1.2)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: activeTrackColor,
          ),
        ],
      ),
    );
  }
}
