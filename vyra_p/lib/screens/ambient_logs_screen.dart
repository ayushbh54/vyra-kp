import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/parent_dashboard_provider.dart';
import '../models/ambient_log_item.dart';

class AmbientLogsScreen extends StatefulWidget {
  const AmbientLogsScreen({super.key});

  @override
  State<AmbientLogsScreen> createState() => _AmbientLogsScreenState();
}

class _AmbientLogsScreenState extends State<AmbientLogsScreen> {
  String? _playingId;
  final Set<String> _expandedLogIds = {'ambient_1'}; // Expand the first one by default

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ParentDashboardProvider>();
    final logs = provider.ambientLogs;
    final totalSeconds = logs.fold<int>(0, (sum, item) => sum + item.durationSeconds);
    final flaggedCount = logs.where((l) => l.isFlagged).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Ambient Voice Intelligence',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Intelligence Summary Card
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
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.graphic_eq_rounded, color: Color(0xFF38BDF8), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Gemini 3.8 Flash Diarization",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              Text(
                                '${provider.activeChild.name} • Screen-Off Capture',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'AI ACTIVE',
                          style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatColumn(label: 'Conversations', value: '${logs.length}'),
                      _StatColumn(
                        label: 'Total Audio',
                        value: '${totalSeconds ~/ 60}m ${totalSeconds % 60}s',
                      ),
                      _StatColumn(
                        label: 'Cloud Purged',
                        value: '${provider.totalCloudPurgedMb.toStringAsFixed(1)} MB',
                        color: const Color(0xFF10B981),
                      ),
                      _StatColumn(
                        label: 'Keywords Hit',
                        value: '$flaggedCount',
                        color: flaggedCount > 0 ? Colors.redAccent : const Color(0xFF10B981),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Cloud Storage Auto-Purge & Battery Conservation Banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.bolt_rounded, color: Color(0xFF10B981), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cloud Auto-Purge Active (0 MB Cloud Bloat)',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Heavy audio is wiped from cloud storage post-sync. Permanent transcripts & voice profiles stay forever. Child battery drain: ~0%.',
                          style: TextStyle(color: const Color(0xFF94A3B8), fontSize: 10, height: 1.2),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: provider.autoPurgeCloudStorage,
                    onChanged: (val) => provider.toggleAutoPurgeCloudStorage(),
                    activeTrackColor: const Color(0xFF10B981),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const Text(
              'Pocket Voice Soundbites & Screenplay',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Accurate Hindi/Hinglish transcripts with speaker vocal profiling.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 14),

            // Soundbite Cards List or Armed Waiting State
            if (logs.isEmpty)
              _buildEmptyArmedState(context, provider)
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: logs.length,
                itemBuilder: (context, index) {
                final item = logs[index];
                final isPlaying = _playingId == item.id;
                final isExpanded = _expandedLogIds.contains(item.id);
                final timeStr = DateFormat('hh:mm a').format(item.timestamp);

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: item.isFlagged
                          ? Colors.redAccent.withValues(alpha: 0.5)
                          : const Color(0xFF334155),
                      width: item.isFlagged ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Card Header
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      timeStr,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        item.formattedDuration,
                                        style: const TextStyle(
                                          color: Color(0xFF38BDF8),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    // Cloud Purge Indicator Chip
                                    if (item.isPurgedFromCloud)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.cloud_done_rounded, color: Color(0xFF10B981), size: 10),
                                            const SizedBox(width: 3),
                                            Text(
                                              'PURGED (${(item.storageFreedKb / 1024).toStringAsFixed(1)}MB)',
                                              style: const TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                if (item.isFlagged && item.detectedKeyword != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 12),
                                        const SizedBox(width: 4),
                                        Text(
                                          'ALERT: "${item.detectedKeyword}"',
                                          style: const TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, size: 13, color: Color(0xFF94A3B8)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    item.locationContext,
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Summary
                            if (item.conversationSummary.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  item.conversationSummary,
                                  style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12, height: 1.3),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Speaker Acoustic Voice Profiles Bar
                      if (item.speakers.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: const BoxDecoration(
                            color: Color(0xFF162032),
                            border: Border(
                              top: BorderSide(color: Color(0xFF334155), width: 0.8),
                              bottom: BorderSide(color: Color(0xFF334155), width: 0.8),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.record_voice_over_rounded, size: 14, color: Color(0xFF38BDF8)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Identified Speakers (${item.speakers.length}):',
                                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: item.speakers.map((spk) {
                                  return InkWell(
                                    onTap: () => _showSpeakerProfileModal(context, spk),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: spk.isChild
                                            ? const Color(0xFF0284C7).withValues(alpha: 0.3)
                                            : const Color(0xFF334155),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: spk.isChild
                                              ? const Color(0xFF38BDF8)
                                              : const Color(0xFF475569),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            spk.isChild ? Icons.face_rounded : Icons.person_outline_rounded,
                                            size: 14,
                                            color: spk.isChild ? const Color(0xFF38BDF8) : Colors.white,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            spk.displayName,
                                            style: TextStyle(
                                              color: spk.isChild ? const Color(0xFF38BDF8) : Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.black26,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              spk.tone.split('&').first.trim(),
                                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),

                      // Turn-by-Turn Screenplay Dialogue Section
                      if (item.dialogue.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    if (isExpanded) {
                                      _expandedLogIds.remove(item.id);
                                    } else {
                                      _expandedLogIds.add(item.id);
                                    }
                                  });
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.forum_outlined, size: 15, color: Color(0xFFF59E0B)),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Full Conversational Script (${item.dialogue.length} lines)',
                                          style: const TextStyle(
                                            color: Color(0xFFF59E0B),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Icon(
                                      isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                      color: const Color(0xFF94A3B8),
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                              if (isExpanded) ...[
                                const SizedBox(height: 12),
                                ...item.dialogue.map((turn) {
                                  final isChild = turn.speakerName.contains('Aryan');
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isChild
                                          ? const Color(0xFF0F172A)
                                          : const Color(0xFF1E293B).withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isChild
                                            ? const Color(0xFF0284C7).withValues(alpha: 0.4)
                                            : const Color(0xFF475569).withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  isChild ? Icons.face : Icons.person_pin_circle_rounded,
                                                  size: 13,
                                                  color: isChild ? const Color(0xFF38BDF8) : const Color(0xFFF59E0B),
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  turn.speakerName,
                                                  style: TextStyle(
                                                    color: isChild ? const Color(0xFF38BDF8) : const Color(0xFFF59E0B),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '[${turn.timestamp}]',
                                                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                                                ),
                                              ],
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.white10,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                turn.emotion,
                                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          turn.hindiText,
                                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Translation: "${turn.englishText}"',
                                          style: const TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),

                      // Bottom Action Bar (Playback & Purge)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0F172A),
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                        ),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () {
                                if (item.isPurgedFromCloud) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Raw audio was purged from cloud to prevent storage overflow. The full screenplay script is saved!'),
                                      backgroundColor: Color(0xFF0284C7),
                                      duration: Duration(seconds: 3),
                                    ),
                                  );
                                } else {
                                  setState(() {
                                    _playingId = isPlaying ? null : item.id;
                                  });
                                }
                              },
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: item.isPurgedFromCloud
                                      ? const Color(0xFF334155)
                                      : (isPlaying ? const Color(0xFF10B981) : const Color(0xFF0284C7)),
                                ),
                                child: Icon(
                                  item.isPurgedFromCloud
                                      ? Icons.description_rounded
                                      : (isPlaying ? Icons.pause : Icons.play_arrow),
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item.isPurgedFromCloud
                                    ? 'Audio Purged (Storage Saved) • Script Retained'
                                    : (isPlaying ? 'Playing studio audio...' : 'Tap to play audio'),
                                style: TextStyle(
                                  color: item.isPurgedFromCloud ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                  fontSize: 11,
                                  fontWeight: item.isPurgedFromCloud ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (!item.isPurgedFromCloud)
                              TextButton.icon(
                                onPressed: () => provider.purgeCloudAudio(item.id),
                                icon: const Icon(Icons.delete_sweep_rounded, color: Colors.orangeAccent, size: 14),
                                label: const Text(
                                  'Purge Media',
                                  style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSpeakerProfileModal(BuildContext context, SpeakerVoiceProfile spk) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      spk.isChild ? Icons.face : Icons.record_voice_over_rounded,
                      color: const Color(0xFF38BDF8),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spk.displayName,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Acoustic Fingerprint by Gemini 3.8 Flash',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _DetailRow(label: 'Pitch', value: spk.pitch),
              const SizedBox(height: 8),
              _DetailRow(label: 'Tone & Style', value: spk.tone),
              const SizedBox(height: 8),
              _DetailRow(label: 'Vocal Profile', value: spk.acousticDescription),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close Profile', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyArmedState(BuildContext context, ParentDashboardProvider provider) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic_none_rounded, color: Color(0xFF38BDF8), size: 40),
          ),
          const SizedBox(height: 16),
          const Text(
            'Pocket Voice Logger Armed & Active',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'To prevent Android\'s Green Dot 🟢 from exposing the monitoring app to ${provider.activeChild.name}, ambient soundbites are automatically captured whenever the child locks their screen or puts their phone in their pocket (Screen-Off).\n\nAs soon as an ambient soundbite is finalized, it will automatically appear here with audio playback and screenplay transcripts.',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_rounded, color: Color(0xFF10B981), size: 16),
                SizedBox(width: 8),
                Text(
                  'Anti-Green-Dot Stealth Guard: ENABLED',
                  style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, '/calls');
                  },
                  icon: const Icon(Icons.phone_in_talk, size: 16),
                  label: const Text('View Call Recordings', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E88E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showVoiceIntercomDialog(context, provider),
                  icon: const Icon(Icons.campaign_rounded, size: 16, color: Color(0xFF38BDF8)),
                  label: const Text('Voice Intercom', style: TextStyle(fontSize: 12, color: Color(0xFF38BDF8))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showVoiceIntercomDialog(BuildContext context, ParentDashboardProvider provider) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.campaign_rounded, color: Color(0xFF38BDF8)),
            SizedBox(width: 8),
            Text('Remote Voice Intercom', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Broadcast an instant voice announcement directly through ${provider.activeChild.name}\'s phone speaker:',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'e.g. Aryan, call me back immediately!',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                provider.sendVoiceIntercom(text);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Intercom broadcast dispatched to ${provider.activeChild.name}'),
                    backgroundColor: const Color(0xFF10B981),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            child: const Text('Broadcast Voice', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13),
        ),
      ],
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatColumn({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color ?? Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
        ),
      ],
    );
  }
}
