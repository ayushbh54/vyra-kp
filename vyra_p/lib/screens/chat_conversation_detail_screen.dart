import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/chat_conversation.dart';
import '../models/chat_message.dart';
import '../providers/parent_dashboard_provider.dart';
import '../widgets/chat_bubble.dart';

class ChatConversationDetailScreen extends StatefulWidget {
  final ChatConversation conversation;

  const ChatConversationDetailScreen({
    super.key,
    required this.conversation,
  });

  @override
  State<ChatConversationDetailScreen> createState() => _ChatConversationDetailScreenState();
}

class _ChatConversationDetailScreenState extends State<ChatConversationDetailScreen> {
  String _searchQuery = '';
  bool _isSearchOpen = false;
  final TextEditingController _searchController = TextEditingController();

  Color _getAppColor(AppType app) {
    switch (app) {
      case AppType.whatsApp:
        return const Color(0xFF25D366);
      case AppType.telegram:
        return const Color(0xFF2AABEE);
      case AppType.instagram:
        return const Color(0xFFE1306C);
      case AppType.snapchat:
        return const Color(0xFFFFFC00);
      case AppType.sms:
        return const Color(0xFF38BDF8);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ParentDashboardProvider>();
    final appColor = _getAppColor(widget.conversation.appType);

    // Get current updated messages for this contact from provider
    final allMessages = provider.allArchivedChatMessages.where((m) {
      final key = m.contactIdentifier.isNotEmpty ? m.contactIdentifier : m.contactName;
      return key == widget.conversation.contactIdentifier && m.appType == widget.conversation.appType;
    }).toList();

    // Fallback if none in provider
    final sourceMessages = allMessages.isNotEmpty ? allMessages : widget.conversation.messages;

    // Filter by search inside conversation if active
    final displayMessages = sourceMessages.where((m) {
      if (_searchQuery.isEmpty) return true;
      return m.messageText.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    // Sort chronologically (oldest at top -> newest at bottom) for standard chat app layout
    displayMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final isWatchlist = widget.conversation.isWatchlistTarget ||
        provider.watchlistTargets.any((t) =>
            t.identifier == widget.conversation.contactIdentifier ||
            t.name == widget.conversation.contactName);

    final hasDeleted = sourceMessages.any((m) => m.isDeletedBackup);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: _isSearchOpen
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Search in this conversation...',
                  hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              )
            : Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 19,
                        backgroundColor: appColor.withValues(alpha: 0.2),
                        child: Text(
                          widget.conversation.contactName.isNotEmpty
                              ? widget.conversation.contactName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: appColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Color(0xFF1E293B),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            widget.conversation.appType.iconAsset,
                            style: const TextStyle(fontSize: 9),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.conversation.contactName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isWatchlist) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.redAccent, width: 0.8),
                                ),
                                child: const Text(
                                  'WATCHLIST',
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${widget.conversation.contactIdentifier} • ${widget.conversation.appType.displayName}',
                          style: TextStyle(
                            color: appColor.withValues(alpha: 0.85),
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          if (_isSearchOpen)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                setState(() {
                  _isSearchOpen = false;
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
              tooltip: 'Search messages',
              onPressed: () => setState(() => _isSearchOpen = true),
            ),
            if (!isWatchlist)
              IconButton(
                icon: const Icon(Icons.shield_outlined, color: Color(0xFF38BDF8)),
                tooltip: 'Add contact to Watchlist',
                onPressed: () {
                  provider.addWatchlistTarget(
                    widget.conversation.contactName,
                    widget.conversation.contactIdentifier,
                    'Added from monitored ${widget.conversation.appType.displayName} chats',
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Added ${widget.conversation.contactName} to Watchlist targets'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                },
              ),
          ],
        ],
      ),
      body: Column(
        children: [
          // 🛡️ Stealth Recovered Messages Alert Banner
          if (hasDeleted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF881337).withValues(alpha: 0.35),
                border: const Border(bottom: BorderSide(color: Color(0xFFE11D48), width: 0.8)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.history_toggle_off, color: Color(0xFFFB7185), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Anti-Delete Active: Sender deleted messages were captured & preserved.',
                      style: TextStyle(color: Color(0xFFFECDD3), fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

          // Messages Timeline
          Expanded(
            child: displayMessages.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isNotEmpty
                          ? 'No messages match "$_searchQuery"'
                          : 'No messages recorded yet.',
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    itemCount: displayMessages.length,
                    itemBuilder: (context, index) {
                      final msg = displayMessages[index];
                      final showDateSeparator = index == 0 ||
                          !_isSameDay(displayMessages[index - 1].timestamp, msg.timestamp);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDateSeparator) _buildDateHeader(msg.timestamp),
                          ChatBubble(message: msg),
                        ],
                      );
                    },
                  ),
          ),

          // Bottom Telemetry Info Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              border: Border(top: BorderSide(color: Color(0xFF334155), width: 0.8)),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_clock, color: appColor, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mirrored in real-time from ${provider.activeChild.name}\'s ${provider.activeChild.deviceModel}',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Text(
                    '${sourceMessages.length} msgs',
                    style: TextStyle(color: appColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildDateHeader(DateTime date) {
    final now = DateTime.now();
    String label;
    if (_isSameDay(date, now)) {
      label = 'Today';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      label = 'Yesterday';
    } else {
      label = DateFormat('EEEE, dd MMM').format(date);
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
