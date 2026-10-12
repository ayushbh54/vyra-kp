import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/call_record.dart';
import '../services/audio_playback_service.dart';

class AudioPlayerCard extends StatelessWidget {
  final CallRecord record;
  final bool isPlaying;
  final VoidCallback onPlayToggle;

  const AudioPlayerCard({
    super.key,
    required this.record,
    required this.isPlaying,
    required this.onPlayToggle,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('hh:mm a • dd MMM').format(record.timestamp);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: record.isTamperAttemptDetected
              ? Colors.amber.shade700
              : (record.isWatchlistTarget ? Colors.redAccent.withValues(alpha: 0.6) : const Color(0xFF334155)),
          width: (record.isTamperAttemptDetected || record.isWatchlistTarget) ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Contact Info & Tags
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: record.callType == CallType.incoming
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.blue.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  record.callType == CallType.incoming ? Icons.call_received : Icons.call_made,
                  color: record.callType == CallType.incoming ? Colors.greenAccent : Colors.lightBlueAccent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.contactName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$timeStr • Duration: ${record.formattedDuration}',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (record.isWatchlistTarget)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'WATCHLIST',
                    style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),

          // Tamper alert badge (Solution A)
          if (record.isTamperAttemptDetected) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade700, width: 0.8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 16),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Anti-Tamper: Child attempted to stop recording. Auto-resumed by Vyra.',
                      style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          const Divider(color: Color(0xFF334155), height: 1),
          const SizedBox(height: 12),

          // Row 2: Audio Player Bar
          Builder(
            builder: (context) {
              final hasRecording = record.recordingUrl != null && record.recordingUrl!.trim().isNotEmpty;
              final audioService = AudioPlaybackService.instance;
              final isCurrentTrack = audioService.currentMediaId == record.id;
              final currentPos = (isCurrentTrack && isPlaying) ? audioService.position : Duration.zero;
              final totalDur = (isCurrentTrack && audioService.duration > Duration.zero)
                  ? audioService.duration
                  : Duration(seconds: record.durationSeconds);

              final progress = (totalDur.inMilliseconds > 0)
                  ? (currentPos.inMilliseconds / totalDur.inMilliseconds).clamp(0.0, 1.0)
                  : 0.0;

              String formatD(Duration d) {
                final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
                final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
                return '$m:$s';
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: hasRecording ? onPlayToggle : null,
                        icon: Icon(
                          !hasRecording
                              ? Icons.mic_off_outlined
                              : (isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
                          color: !hasRecording
                              ? const Color(0xFF64748B)
                              : const Color(0xFF00E676),
                          size: 36,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: isPlaying ? progress : 0.0,
                                backgroundColor: const Color(0xFF334155),
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00E676)),
                                minHeight: 6,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  isPlaying ? formatD(currentPos) : '00:00',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                ),
                                Text(
                                  hasRecording ? record.formattedDuration : 'No Audio File',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (isCurrentTrack && audioService.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 8),
                      child: Text(
                        audioService.errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
