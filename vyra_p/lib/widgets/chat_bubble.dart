import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/chat_message.dart';

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
          color: isIncoming ? const Color(0xFF1E293B) : const Color(0xFF1E88E5),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isIncoming ? const Radius.circular(4) : const Radius.circular(16),
            bottomRight: isIncoming ? const Radius.circular(16) : const Radius.circular(4),
          ),
          border: Border.all(
            color: isIncoming
                ? (message.isWatchlistTarget ? Colors.redAccent.withValues(alpha: 0.5) : const Color(0xFF334155))
                : Colors.transparent,
            width: message.isWatchlistTarget ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: isIncoming ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            // Sender name & tags
            if (isIncoming) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.contactName,
                    style: TextStyle(
                      color: message.isWatchlistTarget ? Colors.redAccent : const Color(0xFF38BDF8),
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
            ],

            // Message text
            Text(
              message.messageText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),

            // Bottom row: Time + 'Saved from Delete' indicator
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.isDeletedBackup) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE11D48).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_toggle_off, size: 10, color: Color(0xFFFB7185)),
                        SizedBox(width: 3),
                        Text(
                          'Preserved (Deleted by Sender)',
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
