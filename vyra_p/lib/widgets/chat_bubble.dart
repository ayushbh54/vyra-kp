import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/chat_message.dart';
import '../providers/parent_dashboard_provider.dart';
import '../services/audio_playback_service.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isIncoming = message.isIncoming;
    final timeStr = DateFormat('hh:mm a').format(message.timestamp);

    return Align(
      alignment: isIncoming ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: message.isDeletedBackup
              ? const Color(0xFF4C0519).withValues(alpha: 0.85)
              : (isIncoming ? const Color(0xFF1E293B) : const Color(0xFF1E88E5)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isIncoming ? const Radius.circular(4) : const Radius.circular(16),
            bottomRight: isIncoming ? const Radius.circular(16) : const Radius.circular(4),
          ),
          border: Border.all(
            color: message.isDeletedBackup
                ? const Color(0xFFFB7185)
                : (message.isWatchlistTarget
                    ? Colors.redAccent.withValues(alpha: 0.5)
                    : (isIncoming ? const Color(0xFF334155) : Colors.transparent)),
            width: (message.isDeletedBackup || message.isWatchlistTarget) ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: isIncoming ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            // Prominent Anti-Delete Banner
            if (message.isDeletedBackup) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF881337).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE11D48), width: 0.8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_forever_rounded, size: 12, color: Color(0xFFFECDD3)),
                    SizedBox(width: 4),
                    Text(
                      'Deleted for Everyone (Saved by Vyra)',
                      style: TextStyle(
                        color: Color(0xFFFECDD3),
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 👁️ 1-View (View Once) Banner (Both Incoming & Outgoing captured)
            if (message.isViewOnce) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isIncoming
                      ? const Color(0xFF581C87).withValues(alpha: 0.7)
                      : const Color(0xFF0369A1).withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isIncoming ? const Color(0xFFA855F7) : const Color(0xFF38BDF8),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_off_rounded,
                      size: 12,
                      color: isIncoming ? const Color(0xFFE9D5FF) : const Color(0xFFBAE6FD),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isIncoming
                          ? '👁️ Incoming 1-View (Captured before vanishing)'
                          : '👁️ Outgoing 1-View (Sent by child)',
                      style: TextStyle(
                        color: isIncoming ? const Color(0xFFF3E8FF) : const Color(0xFFF0F9FF),
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Sender & Direction tags
            if (isIncoming) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_outline_rounded, size: 11, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 4),
                  Text(
                    (message.contactName == 'WhatsApp Contact' || message.contactName == 'Instagram Contact' || message.contactName == 'Snapchat Chat')
                        ? 'Received Message'
                        : message.contactName,
                    style: TextStyle(
                      color: message.isWatchlistTarget
                          ? Colors.redAccent
                          : (message.isDeletedBackup ? const Color(0xFFFDA4AF) : const Color(0xFF38BDF8)),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  if (message.isWatchlistTarget) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'WATCHLIST',
                        style: TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
            ] else ...[
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 11, color: Color(0xFFBAE6FD)),
                  SizedBox(width: 4),
                  Text(
                    'Sent by Aryan (Child)',
                    style: TextStyle(
                      color: Color(0xFFBAE6FD),
                      fontWeight: FontWeight.w600,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],

            // Message text
            Text(
              message.messageText,
              style: TextStyle(
                color: message.isDeletedBackup ? const Color(0xFFFFF1F2) : Colors.white,
                fontSize: 14,
                height: 1.3,
                fontWeight: message.isDeletedBackup ? FontWeight.w500 : FontWeight.normal,
              ),
            ),

            // 📸 Media Preview: Image / 1-View Snap / Video
            if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => Dialog(
                      backgroundColor: Colors.transparent,
                      insetPadding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Align(
                            alignment: Alignment.topRight,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white, size: 28),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              message.mediaUrl!,
                              fit: BoxFit.contain,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return const Padding(
                                  padding: EdgeInsets.all(40),
                                  child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) => Container(
                                padding: const EdgeInsets.all(24),
                                color: const Color(0xFF1E293B),
                                child: const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.broken_image, color: Colors.white60, size: 48),
                                    SizedBox(height: 8),
                                    Text('Media expired or syncing from vault', style: TextStyle(color: Colors.white70)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 200, maxWidth: 260),
                    color: Colors.black26,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.network(
                          message.mediaUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, e, st) => Container(
                            height: 120,
                            color: const Color(0xFF1E293B),
                            child: const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.image, color: Color(0xFF38BDF8), size: 20),
                                  SizedBox(width: 8),
                                  Text('Tap to view photo', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (message.mediaType == 'video' || message.messageText.contains('Video'))
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white70, width: 1.5),
                            ),
                            child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ] else if (message.isViewOnce ||
                message.messageText.contains('📷') ||
                message.messageText.contains('Photo') ||
                message.messageText.contains('Snap') ||
                message.messageText.contains('🎥') ||
                message.messageText.contains('Video')) ...[
              // Styled Media Card when URL is locally stored on child phone
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: message.isViewOnce
                        ? (isIncoming ? const Color(0xFFA855F7) : const Color(0xFF38BDF8))
                        : Colors.white12,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (message.isViewOnce
                                ? (isIncoming ? const Color(0xFF7E22CE) : const Color(0xFF0284C7))
                                : const Color(0xFF0F172A))
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        (message.messageText.contains('🎥') || message.messageText.contains('Video'))
                            ? Icons.videocam
                            : (message.isViewOnce ? Icons.visibility_off : Icons.photo_camera),
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (message.messageText.contains('🎥') || message.messageText.contains('Video'))
                              ? 'Video Media File'
                              : (message.isViewOnce ? '1-View Photo Snapshot' : 'Shared Photo'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          isIncoming ? 'Saved from recipient screen' : 'Captured from child phone',
                          style: const TextStyle(color: Colors.white60, fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Optional Voice Note bar
            if (message.voiceNoteUrl != null && message.voiceNoteUrl!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Consumer<ParentDashboardProvider>(
                builder: (context, provider, _) {
                  final isCurrentPlaying = provider.currentlyPlayingAudioId == message.id &&
                      AudioPlaybackService.instance.isPlaying;
                  return InkWell(
                    onTap: () {
                      provider.togglePlayAudioUrl(message.id, message.voiceNoteUrl!);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: isCurrentPlaying
                            ? const Color(0xFF0369A1).withValues(alpha: 0.5)
                            : Colors.black38,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCurrentPlaying ? const Color(0xFF38BDF8) : Colors.white24,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isCurrentPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                            color: const Color(0xFF38BDF8),
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isCurrentPlaying ? 'Playing Voice Note...' : 'Voice Note (${message.voiceNoteDurationSeconds ?? 0}s)',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],

            const SizedBox(height: 6),

            // Bottom row: Time + 'Saved from Delete' indicator
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.isDeletedBackup) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE11D48).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_toggle_off, size: 10, color: Color(0xFFFB7185)),
                        SizedBox(width: 3),
                        Text(
                          'Preserved',
                          style: TextStyle(color: Color(0xFFFB7185), fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  timeStr,
                  style: TextStyle(
                    color: isIncoming ? const Color(0xFF94A3B8) : Colors.white70,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
