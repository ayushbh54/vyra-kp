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
            if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty && message.mediaType != 'audio') ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showMediaViewer(context, message),
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
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    (message.mediaType == 'video' || message.messageText.contains('Video'))
                                        ? Icons.videocam
                                        : Icons.image,
                                    color: const Color(0xFF38BDF8),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    (message.mediaType == 'video' || message.messageText.contains('Video'))
                                        ? 'Tap to play video'
                                        : 'Tap to view photo',
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (message.mediaType == 'video' || message.messageText.contains('Video'))
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF38BDF8), width: 2),
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
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
              // 🎥 Working Interactive Media Card (Child Storage / Vault)
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _showMediaVaultModal(context, message),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: message.isViewOnce
                          ? (isIncoming ? const Color(0xFFA855F7) : const Color(0xFF38BDF8))
                          : Colors.white24,
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
                              .withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (message.messageText.contains('🎥') || message.messageText.contains('Video'))
                                ? const Color(0xFF38BDF8)
                                : Colors.transparent,
                            width: 0.8,
                          ),
                        ),
                        child: Icon(
                          (message.messageText.contains('🎥') || message.messageText.contains('Video'))
                              ? Icons.videocam_rounded
                              : (message.isViewOnce ? Icons.visibility_off_rounded : Icons.photo_camera_rounded),
                          color: const Color(0xFF38BDF8),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
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
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.touch_app_rounded, size: 9, color: Color(0xFF38BDF8)),
                                      SizedBox(width: 2),
                                      Text('Tap to play', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isIncoming ? 'Saved from recipient screen • Tap to stream' : 'Captured from child phone • Tap to play',
                              style: const TextStyle(color: Colors.white70, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // 🎙️ Functional Voice Note Player Bar
            if ((message.voiceNoteUrl != null && message.voiceNoteUrl!.isNotEmpty) ||
                (message.mediaType == 'audio' && message.mediaUrl != null && message.mediaUrl!.isNotEmpty)) ...[
              const SizedBox(height: 6),
              Consumer<ParentDashboardProvider>(
                builder: (context, provider, _) {
                  final voiceUrl = (message.voiceNoteUrl != null && message.voiceNoteUrl!.isNotEmpty)
                      ? message.voiceNoteUrl!
                      : message.mediaUrl!;
                  final isCurrentPlaying = provider.currentlyPlayingAudioId == message.id &&
                      AudioPlaybackService.instance.isPlaying;
                  return InkWell(
                    onTap: () {
                      provider.togglePlayAudioUrl(message.id, voiceUrl);
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

            // Bottom row: Time + 'Saved from Delete' indicator + Dual-Verified badge
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.isDualVerified) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5), width: 0.6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_user_rounded, size: 10, color: Color(0xFF34D399)),
                        SizedBox(width: 3),
                        Text(
                          'Verified 🛡️',
                          style: TextStyle(color: Color(0xFF34D399), fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
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

  void _showMediaViewer(BuildContext context, ChatMessage message) {
    final isVideo = message.mediaType == 'video' || message.messageText.contains('Video');
    final provider = Provider.of<ParentDashboardProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F172A),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white24)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(isVideo ? Icons.videocam_rounded : Icons.photo_rounded, color: const Color(0xFF38BDF8), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        isVideo ? 'Video Media Player' : 'Photo Viewer',
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 24),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 16),
              if (isVideo) ...[
                // Video Player Card with Live Audio Stream
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.videocam_rounded, color: Color(0xFF38BDF8), size: 48),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Video from ${message.contactName}',
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Stream active • Supabase Cloud Vault',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                      ),
                      const SizedBox(height: 20),
                      Consumer<ParentDashboardProvider>(
                        builder: (context, prov, _) {
                          final isPlaying = prov.currentlyPlayingAudioId == message.id &&
                              AudioPlaybackService.instance.isPlaying;
                          return ElevatedButton.icon(
                            onPressed: () {
                              prov.togglePlayAudioUrl(message.id, message.mediaUrl!);
                            },
                            icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 24),
                            label: Text(
                              isPlaying ? 'Pause Audio Track' : 'Play Video Audio Track',
                              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF38BDF8),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ] else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: InteractiveViewer(
                    child: Image.network(
                      message.mediaUrl!,
                      fit: BoxFit.contain,
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return const Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
                        );
                      },
                      errorBuilder: (ctx, err, stack) => const Padding(
                        padding: EdgeInsets.all(30),
                        child: Text('Image preview loading from vault...', style: TextStyle(color: Colors.white70)),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sender: ${message.contactName}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      provider.syncFromSupabase();
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('🔄 Synced latest vault media!')),
                      );
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 14, color: Color(0xFF38BDF8)),
                    label: const Text('Refresh Vault', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMediaVaultModal(BuildContext context, ChatMessage message) {
    final isVideo = message.messageText.contains('🎥') || message.messageText.contains('Video');
    final provider = Provider.of<ParentDashboardProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: Colors.white24, width: 0.5),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isVideo ? Icons.videocam_rounded : Icons.photo_camera_rounded,
                    color: const Color(0xFF38BDF8),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isVideo ? 'WhatsApp Video Captured' : 'WhatsApp Photo Captured',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Detected in chat with ${message.contactName}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFF38BDF8), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Media is currently stored securely on the child device storage. Tap below to prioritize upload and stream directly to your iPhone.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Text('Requesting ${isVideo ? "video" : "photo"} from child device...'),
                        ],
                      ),
                      duration: const Duration(seconds: 4),
                      backgroundColor: const Color(0xFF0369A1),
                    ),
                  );
                  await provider.requestMediaSync(message.contactName, message.id, isVideo: isVideo);
                },
                icon: const Icon(Icons.bolt_rounded, color: Colors.black, size: 20),
                label: Text(
                  isVideo ? '⚡ Fetch & Play Video Now' : '⚡ Fetch & View Photo Now',
                  style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () {
                  provider.syncFromSupabase();
                  provider.triggerLanSync();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('🔄 Cloud and LAN sync refreshed!')),
                  );
                },
                icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white70),
                label: const Text('Refresh from Cloud Vault', style: TextStyle(color: Colors.white70, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
