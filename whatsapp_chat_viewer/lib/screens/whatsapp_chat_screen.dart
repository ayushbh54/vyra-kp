import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/whatsapp_conversation.dart';
import '../providers/whatsapp_viewer_provider.dart';
import '../theme/whatsapp_theme.dart';
import '../widgets/chat_bubble.dart';

class WhatsAppChatScreen extends StatefulWidget {
  final WhatsAppConversation conversation;

  const WhatsAppChatScreen({super.key, required this.conversation});

  @override
  State<WhatsAppChatScreen> createState() => _WhatsAppChatScreenState();
}

class _WhatsAppChatScreenState extends State<WhatsAppChatScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showOnlyDeleted = false;
  String _inChatSearch = '';
  bool _isSearching = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WhatsAppViewerProvider>();
    final allChatMsgs = provider.messages;

    final displayMsgs = allChatMsgs.where((m) {
      if (_showOnlyDeleted && !m.isDeleted) return false;
      if (_inChatSearch.isNotEmpty && !m.text.toLowerCase().contains(_inChatSearch.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    final deletedCount = allChatMsgs.where((m) => m.isDeleted).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0B141A), // Authentic WhatsApp dark wallpaper background
      appBar: AppBar(
        backgroundColor: WhatsAppTheme.appBarBg,
        elevation: 1,
        leadingWidth: 75,
        leading: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: WhatsAppTheme.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            CircleAvatar(
              radius: 17,
              backgroundColor: widget.conversation.isGroup
                  ? WhatsAppTheme.primaryGreen.withValues(alpha: 0.3)
                  : WhatsAppTheme.accentBlue.withValues(alpha: 0.3),
              child: Icon(
                widget.conversation.isGroup ? Icons.groups_rounded : Icons.person_rounded,
                color: widget.conversation.isGroup ? WhatsAppTheme.primaryGreen : WhatsAppTheme.accentBlue,
                size: 20,
              ),
            ),
          ],
        ),
        title: _isSearching
            ? TextField(
                autofocus: true,
                style: const TextStyle(color: WhatsAppTheme.textPrimary, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Search in conversation...',
                  hintStyle: TextStyle(color: WhatsAppTheme.textSecondary, fontSize: 14),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _inChatSearch = v),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.conversation.name,
                    style: const TextStyle(
                      color: WhatsAppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.conversation.isGroup
                        ? 'Group • ${allChatMsgs.length} messages'
                        : (deletedCount > 0 ? '$deletedCount deleted messages captured' : '${allChatMsgs.length} messages'),
                    style: TextStyle(
                      color: deletedCount > 0 ? WhatsAppTheme.deletedColor : WhatsAppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: WhatsAppTheme.textSecondary),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _inChatSearch = '';
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          if (deletedCount > 0)
            IconButton(
              icon: Icon(
                _showOnlyDeleted ? Icons.block_flipped : Icons.filter_alt_outlined,
                color: _showOnlyDeleted ? WhatsAppTheme.deletedColor : WhatsAppTheme.textSecondary,
              ),
              tooltip: _showOnlyDeleted ? 'Show All Messages' : 'Show Only Deleted Messages',
              onPressed: () => setState(() => _showOnlyDeleted = !_showOnlyDeleted),
            ),
        ],
      ),
      body: displayMsgs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded, color: WhatsAppTheme.textSecondary, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    _showOnlyDeleted ? 'No deleted messages in this thread.' : 'No messages found.',
                    style: const TextStyle(color: WhatsAppTheme.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: 10, bottom: 20),
              itemCount: displayMsgs.length,
              itemBuilder: (context, index) {
                final msg = displayMsgs[index];
                final showDateChip = index == 0 ||
                    !_isSameDay(displayMsgs[index - 1].timestamp, msg.timestamp);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showDateChip) _buildDateChip(msg.timestamp),
                    WhatsAppChatBubble(message: msg),
                  ],
                );
              },
            ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildDateChip(DateTime dt) {
    final now = DateTime.now();
    String text;
    if (_isSameDay(dt, now)) {
      text = 'TODAY';
    } else if (_isSameDay(dt, now.subtract(const Duration(days: 1)))) {
      text = 'YESTERDAY';
    } else {
      text = DateFormat('MMMM d, yyyy').format(dt).toUpperCase();
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF182229),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 1,
            ),
          ],
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: WhatsAppTheme.textSecondary,
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
