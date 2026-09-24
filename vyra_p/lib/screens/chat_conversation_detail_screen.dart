import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/chat_conversation.dart';
import '../models/chat_message.dart';
import '../models/call_record.dart';
import '../providers/parent_dashboard_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/audio_player_card.dart';

enum TimelineItemType { chat, call }

class TimelineEntry {
  final DateTime timestamp;
  final TimelineItemType type;
  final ChatMessage? chat;
  final CallRecord? call;

  TimelineEntry.chat(this.chat)
      : timestamp = chat!.timestamp,
        type = TimelineItemType.chat,
        call = null;

  TimelineEntry.call(this.call)
      : timestamp = call!.timestamp,
        type = TimelineItemType.call,
        chat = null;
}

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
  int _selectedTab = 0; // 0 = All Activity, 1 = Chats, 2 = Calls & Audio
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

    // 1. Get updated messages for this contact from provider
    final allMessages = provider.allArchivedChatMessages.where((m) {
      final key = m.contactIdentifier.isNotEmpty ? m.contactIdentifier : m.contactName;
      final matchByIdentifier = key == widget.conversation.contactIdentifier;
      final matchByName = m.contactName.isNotEmpty &&
          m.contactName != 'WhatsApp Contact' &&
          m.contactName != 'Snapchat Chat' &&
          m.contactName.toLowerCase() == widget.conversation.contactName.toLowerCase();
      return (matchByIdentifier || matchByName) && m.appType == widget.conversation.appType;
    }).toList();

    final sourceMessages = allMessages.isNotEmpty ? allMessages : widget.conversation.messages;

    // Filter out scraper garbage
    final cleanMessages = sourceMessages
        .where((m) => !ParentDashboardProvider.isScraperGarbage(m.messageText))
        .toList();

    // Filter by search inside conversation if active
    final displayMessages = cleanMessages.where((m) {
      if (_searchQuery.isEmpty) return true;
      return m.messageText.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    // Sort chronologically (oldest at top -> newest at bottom)
    displayMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // 2. Get call records associated with this person
    final contactCalls = provider.getCallRecordsForContact(
      widget.conversation.contactName,
      widget.conversation.contactIdentifier,
    ).where((c) {
      if (_searchQuery.isEmpty) return true;
      return c.contactName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.phoneNumber.contains(_searchQuery);
    }).toList();
    contactCalls.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // 3. Build unified chronological timeline (Chats + Calls)
    final List<TimelineEntry> unifiedTimeline = [
      ...displayMessages.map((m) => TimelineEntry.chat(m)),
      ...contactCalls.map((c) => TimelineEntry.call(c)),
    ];
    unifiedTimeline.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final isWatchlist = widget.conversation.isWatchlistTarget ||
        provider.watchlistTargets.any((t) =>
            t.identifier == widget.conversation.contactIdentifier ||
            t.name == widget.conversation.contactName);

    final hasDeleted = displayMessages.any((m) => m.isDeletedBackup);

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
          // Sub-Navigation Tabs (All Activity • Chats • Calls)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF162032),
              border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 0.8)),
            ),
            child: Row(
              children: [
                _buildTabButton(
                  index: 0,
                  label: 'All Activity',
                  badgeCount: unifiedTimeline.length,
                  icon: Icons.hub_rounded,
                  color: appColor,
                ),
                const SizedBox(width: 8),
                _buildTabButton(
                  index: 1,
                  label: 'Chats',
                  badgeCount: displayMessages.length,
                  icon: Icons.chat_bubble_outline,
                  color: appColor,
                ),
                const SizedBox(width: 8),
                _buildTabButton(
                  index: 2,
                  label: 'Calls',
                  badgeCount: contactCalls.length,
                  icon: Icons.phone_in_talk,
                  color: const Color(0xFF10B981),
                ),
              ],
            ),
          ),

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

          // Main Content View based on Tab
          Expanded(
            child: _buildSelectedTabContent(
              context: context,
              provider: provider,
              appColor: appColor,
              displayMessages: displayMessages,
              contactCalls: contactCalls,
              unifiedTimeline: unifiedTimeline,
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
                    '${displayMessages.length} msgs • ${contactCalls.length} calls',
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

  Widget _buildTabButton({
    required int index,
    required String label,
    required int badgeCount,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.2) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : const Color(0xFF334155),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isSelected ? color : const Color(0xFF94A3B8)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? color : const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badgeCount',
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedTabContent({
    required BuildContext context,
    required ParentDashboardProvider provider,
    required Color appColor,
    required List<ChatMessage> displayMessages,
    required List<CallRecord> contactCalls,
    required List<TimelineEntry> unifiedTimeline,
  }) {
    if (_selectedTab == 0) {
      // All Activity (Unified Timeline)
      if (unifiedTimeline.isEmpty) {
        return _buildEmptyPlaceholder('No activity recorded for this contact yet.');
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        itemCount: unifiedTimeline.length,
        itemBuilder: (context, index) {
          final item = unifiedTimeline[index];
          final showDateSeparator = index == 0 ||
              !_isSameDay(unifiedTimeline[index - 1].timestamp, item.timestamp);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showDateSeparator) _buildDateHeader(item.timestamp),
              if (item.type == TimelineItemType.chat && item.chat != null)
                ChatBubble(message: item.chat!),
              if (item.type == TimelineItemType.call && item.call != null)
                _buildInlineCallCard(context, item.call!, provider),
            ],
          );
        },
      );
    } else if (_selectedTab == 1) {
      // Chats Only
      if (displayMessages.isEmpty) {
        return _buildEmptyPlaceholder('No chat messages recorded with this contact.');
      }
      return ListView.builder(
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
      );
    } else {
      // Calls Only
      if (contactCalls.isEmpty) {
        return _buildEmptyPlaceholder('No call records or recordings for this contact.');
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: contactCalls.length,
        itemBuilder: (context, index) {
          final call = contactCalls[index];
          final isPlaying = provider.currentlyPlayingAudioId == call.id;

          return AudioPlayerCard(
            record: call,
            isPlaying: isPlaying,
            onPlayToggle: () => provider.togglePlayAudio(call.id),
          );
        },
      );
    }
  }

  Widget _buildEmptyPlaceholder(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox_outlined, color: Color(0xFF64748B), size: 40),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty ? 'No items match "$_searchQuery"' : message,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildInlineCallCard(BuildContext context, CallRecord call, ParentDashboardProvider provider) {
    final isIncoming = call.callType == CallType.incoming;
    final isPlaying = provider.currentlyPlayingAudioId == call.id;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: call.isTamperAttemptDetected
                ? Colors.amber.shade700
                : const Color(0xFF334155),
            width: call.isTamperAttemptDetected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isIncoming
                    ? Colors.green.withValues(alpha: 0.15)
                    : Colors.blue.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isIncoming ? Icons.call_received : Icons.call_made,
                color: isIncoming ? Colors.greenAccent : Colors.lightBlueAccent,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        isIncoming ? 'Incoming Call' : 'Outgoing Call',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${call.formattedDuration})',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('hh:mm a').format(call.timestamp),
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                  ),
                  if (call.isTamperAttemptDetected) ...[
                    const SizedBox(height: 4),
                    const Text(
                      '⚠️ Tamper attempt detected & bypassed',
                      style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                color: const Color(0xFF38BDF8),
                size: 32,
              ),
              onPressed: () => provider.togglePlayAudio(call.id),
              tooltip: isPlaying ? 'Pause recording' : 'Play call recording',
            ),
          ],
        ),
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
