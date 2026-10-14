import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/whatsapp_message.dart';
import '../theme/whatsapp_theme.dart';
import '../services/whatsapp_sanitizer.dart';

class WhatsAppChatBubble extends StatelessWidget {
  final WhatsAppMessage message;

  const WhatsAppChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isIncoming = message.isIncoming;
    final timeStr = DateFormat('h:mm a').format(message.timestamp);

    final bubbleColor = message.isDeleted
        ? WhatsAppTheme.darkDeletedCard
        : (isIncoming ? WhatsAppTheme.darkIncomingBubble : WhatsAppTheme.darkOutgoingBubble);

    final borderColor = message.isDeleted ? WhatsAppTheme.darkDeletedBadge.withValues(alpha: 0.5) : Colors.transparent;

    return Align(
      alignment: isIncoming ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(10),
              topRight: const Radius.circular(10),
              bottomLeft: isIncoming ? Radius.zero : const Radius.circular(10),
              bottomRight: isIncoming ? const Radius.circular(10) : Radius.zero,
            ),
            border: Border.all(color: borderColor, width: message.isDeleted ? 1.0 : 0.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 1.5,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Group Sender Name (Color coded like original WhatsApp)
              if (isIncoming && message.isGroup && message.sender.isNotEmpty && message.sender != 'Unknown')
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    message.sender,
                    style: TextStyle(
                      color: WhatsAppSanitizer.getParticipantColor(message.sender),
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),

              // Deleted Message Warning Banner
              if (message.isDeleted)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block_flipped, color: Color(0xFFEF4444), size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Deleted by Sender (Captured)',
                        style: TextStyle(
                          color: Color(0xFFFCA5A5),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

              // View-Once Snap Badge
              if (message.isViewOnce)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.camera_alt_rounded, color: Color(0xFFF59E0B), size: 12),
                      SizedBox(width: 4),
                      Text(
                        '1-View Snap Preserved',
                        style: TextStyle(
                          color: Color(0xFFFCD34D),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

              // Message Content
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  Text(
                    message.text,
                    style: const TextStyle(
                      color: WhatsAppTheme.darkTextPrimary,
                      fontSize: 14.5,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          timeStr,
                          style: const TextStyle(
                            color: WhatsAppTheme.darkTextSecondary,
                            fontSize: 10.5,
                          ),
                        ),
                        if (!isIncoming) ...[
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.done_all,
                            color: WhatsAppTheme.darkBlueTicks,
                            size: 15,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
