import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/whatsapp_conversation.dart';
import '../providers/whatsapp_viewer_provider.dart';
import '../theme/whatsapp_theme.dart';
import 'whatsapp_chat_screen.dart';

class DeletedChatsDrawer extends StatelessWidget {
  const DeletedChatsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WhatsAppViewerProvider>();
    final deleted = provider.allDeletedMessages;

    return Container(
      decoration: const BoxDecoration(
        color: WhatsAppTheme.scaffoldBg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Header Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: WhatsAppTheme.textSecondary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Drawer Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.block_flipped, color: WhatsAppTheme.deletedColor, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Deleted & Erased Chats',
                          style: TextStyle(
                            color: WhatsAppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${deleted.length} captured messages',
                          style: const TextStyle(
                            color: Color(0xFFFCA5A5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: WhatsAppTheme.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(color: WhatsAppTheme.dividerColor, height: 1),

          // List of Deleted Messages
          Expanded(
            child: deleted.isEmpty
                ? const Center(
                    child: Text(
                      'No deleted messages captured yet.',
                      style: TextStyle(color: WhatsAppTheme.textSecondary, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: deleted.length,
                    separatorBuilder: (context, index) => const Divider(
                      color: WhatsAppTheme.dividerColor,
                      height: 1,
                      indent: 64,
                    ),
                    itemBuilder: (context, index) {
                      final msg = deleted[index];
                      final timeStr = DateFormat('MMM d, h:mm a').format(msg.timestamp);

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red.withValues(alpha: 0.2),
                          child: const Icon(Icons.block_flipped, color: WhatsAppTheme.deletedColor, size: 18),
                        ),
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                msg.sender.isNotEmpty ? msg.sender : 'Sender',
                                style: const TextStyle(
                                  color: WhatsAppTheme.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                color: WhatsAppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2E151B),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFF7F1D1D)),
                                ),
                                child: Text(
                                  msg.text,
                                  style: const TextStyle(
                                    color: Color(0xFFFEE2E2),
                                    fontSize: 13,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context); // close sheet
                          final conv = provider.conversations.firstWhere(
                            (c) => c.id == msg.threadId || c.name == msg.sender,
                            orElse: () => provider.conversations.isNotEmpty
                                ? provider.conversations.first
                                : WhatsAppConversation(
                                    id: msg.threadId,
                                    name: msg.sender,
                                    isGroup: false,
                                  ),
                          );
                          provider.selectConversation(conv);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WhatsAppChatScreen(conversation: conv),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
