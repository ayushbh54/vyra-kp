import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/parent_dashboard_provider.dart';
import '../models/chat_message.dart';
import '../models/chat_conversation.dart';
import 'chat_conversation_detail_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ParentDashboardProvider>();
    final selectedApp = provider.selectedChatApp;
    final selectedRange = provider.selectedChatRange;

    // Filter out scraper noise / junk nodes
    final validMessages = provider.chatMessages.where((msg) {
      if (ParentDashboardProvider.isScraperGarbage(msg.messageText)) return false;
      final matchesApp = msg.appType == selectedApp;
      final matchesSearch = _searchQuery.isEmpty ||
          msg.messageText.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          msg.contactName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          msg.contactIdentifier.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesApp && matchesSearch;
    }).toList();

    // Group messages by contact thread (like WhatsApp / Telegram inbox)
    final Map<String, List<ChatMessage>> grouped = {};
    for (final msg in validMessages) {
      String key = msg.contactIdentifier.isNotEmpty ? msg.contactIdentifier : msg.contactName;
      if (key == 'WhatsApp Contact' || key == 'Snapchat Chat' || key == 'Unknown' || key == 'Instagram Contact') {
        final parsed = ParentDashboardProvider.parseMessageContent(key, msg.messageText, msg.isDeletedBackup);
        if (parsed.sender != key) {
          key = parsed.sender;
        }
      }

      // Normalization for Harshit Kamboj across all apps
      final lowerKey = key.trim().toLowerCase();
      if (lowerKey.contains('harshit') || lowerKey.contains('kamboj')) {
        key = 'Harshit Kamboj';
      }

      grouped.putIfAbsent(key, () => []).add(msg);
    }

    final conversations = grouped.entries
        .where((entry) {
          final k = entry.key.trim().toLowerCase();
          // Never display typing search fragments, UI counters, or generic scraper buckets
          if (k == 'whatsapp contact' ||
              k == 'instagram contact' ||
              k == 'snapchat chat' ||
              k == 'snapchat contact' ||
              k == 'telegram contact' ||
              k == 'social contact' ||
              k == 'unknown' ||
              k == 'messages' ||
              k == 'all messages' ||
              k == 'ha' ||
              k == 'har' ||
              k == 'hars' ||
              k == 'harsh' ||
              k == 'harshi' ||
              k.contains('reshare') ||
              k.contains('view likes') ||
              k.contains('comment number') ||
              k.contains('save number') ||
              k.contains('reposted') ||
              k == 'follow' ||
              k == 'friends' ||
              k.contains('team id') ||
              k.contains('team name') ||
              k.contains('turn on notifications') ||
              k.contains('never miss snaps') ||
              k.contains('add friends') ||
              k.contains('find friends') ||
              k.contains('sent 1-view snap') ||
              k.contains('incoming snap')) {
            return false;
          }
          return true;
        })
        .map((entry) {
      final msgs = entry.value;
      msgs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Resolve best human-readable name in this thread
      String bestContactName = entry.key;
      for (final m in msgs) {
        if (m.contactName.isNotEmpty &&
            m.contactName != 'WhatsApp Contact' &&
            m.contactName != 'Instagram Contact' &&
            m.contactName != 'Snapchat Chat' &&
            m.contactName != 'Unknown') {
          bestContactName = m.contactName;
          break;
        }
      }

      final isWatchlist = msgs.any((m) => m.isWatchlistTarget) ||
          entry.key.toLowerCase().contains('harshit') ||
          entry.key.toLowerCase().contains('kamboj');

      return ChatConversation(
        contactIdentifier: entry.key,
        contactName: bestContactName,
        appType: msgs.first.appType,
        messages: msgs,
        isWatchlistTarget: isWatchlist,
      );
    }).toList();

    conversations.sort((a, b) => b.lastMessage.timestamp.compareTo(a.lastMessage.timestamp));

    final totalAppArchived = provider.allArchivedChatMessages
        .where((m) => m.appType == selectedApp)
        .length;

    // 📸 Filter 1-view snaps & disappearing media captured for this app
    final viewOnceMedia = provider.chatMessages.where((m) {
      if (m.appType != selectedApp) return false;
      return m.isViewOnce ||
          m.mediaType == 'snap' ||
          m.messageText.toLowerCase().contains('1-view') ||
          m.messageText.toLowerCase().contains('view once') ||
          m.contactName.toLowerCase().contains('1-view snap') ||
          (m.mediaUrl != null && m.mediaUrl!.isNotEmpty && m.mediaUrl!.contains('snap'));
    }).toList();
    viewOnceMedia.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Monitored Chats & SMS',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, color: Color(0xFF38BDF8)),
            tooltip: 'Fetch Older Historical Chats',
            onPressed: () => _showDeepHistoricalFetchDialog(context, provider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search chats, contacts, or words...',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
              ),
            ),
          ),

          // App Selection Tabs (WhatsApp, Instagram, Telegram, SMS)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: AppType.values.map((app) {
                final isSelected = app == selectedApp;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    selected: isSelected,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(app.iconAsset),
                        const SizedBox(width: 6),
                        Text(
                          app.displayName,
                          style: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: const Color(0xFF1E293B),
                    selectedColor: const Color(0xFF1E88E5),
                    checkmarkColor: Colors.white,
                    side: BorderSide(
                      color: isSelected ? const Color(0xFF1E88E5) : const Color(0xFF334155),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    onSelected: (_) => provider.setSelectedChatApp(app),
                  ),
                );
              }).toList(),
            ),
          ),

          // 📅 Date Range Selector Strip (Last 2 Days [Default] • 7 Days • 30 Days • All Time)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFF162032),
            child: Row(
              children: [
                const Icon(Icons.date_range_rounded, color: Color(0xFF38BDF8), size: 16),
                const SizedBox(width: 6),
                const Text(
                  'Range:',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ChatDateRange.values.map((range) {
                        final isSelected = range == selectedRange;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () => provider.setSelectedChatRange(range),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                                ),
                              ),
                              child: Text(
                                range == ChatDateRange.last2Days ? '2 Days (Default)' : range.label,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Deep Historical Scan Action Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 0.8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Showing: ${selectedRange.label} (${conversations.length} contacts • ${validMessages.length} msgs)',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      totalAppArchived > validMessages.length
                          ? '${totalAppArchived - validMessages.length} older messages available in deep vault'
                          : 'Tap any contact to view full chat history',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => _showDeepHistoricalFetchDialog(context, provider),
                  icon: const Icon(Icons.download_rounded, color: Color(0xFF38BDF8), size: 14),
                  label: const Text(
                    'Fetch Older',
                    style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.15),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),

          // 📸 Dedicated 1-View Snaps & Media Vault
          if (viewOnceMedia.isNotEmpty)
            _OneViewMediaVaultCard(
              items: viewOnceMedia,
              onTap: () => _show1ViewVaultGallery(context, viewOnceMedia),
            ),

          // Contact Conversation Threads (WhatsApp/Telegram-style Inbox)
          Expanded(
            child: conversations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chat_bubble_outline, color: Color(0xFF64748B), size: 44),
                        const SizedBox(height: 12),
                        Text(
                          'No conversations found in ${selectedApp.displayName} within ${selectedRange.label}.',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: () => provider.setSelectedChatRange(ChatDateRange.allTime),
                          icon: const Icon(Icons.all_inclusive, size: 16),
                          label: const Text('Switch to "All Time" View', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E88E5),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    itemCount: conversations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final conv = conversations[index];
                      return _ConversationThreadCard(
                        conversation: conv,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatConversationDetailScreen(conversation: conv),
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

  void _showDeepHistoricalFetchDialog(BuildContext context, ParentDashboardProvider provider) {
    int selectedDays = 7;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.history_toggle_off_rounded, color: Color(0xFF38BDF8), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Fetch Older History',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select how far back you want to fetch and scan chats from the child device:',
                  style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 12),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _DayChoiceChip(
                      label: 'Last 7 Days',
                      isSelected: selectedDays == 7,
                      onTap: () => setDialogState(() => selectedDays = 7),
                    ),
                    _DayChoiceChip(
                      label: 'Last 15 Days',
                      isSelected: selectedDays == 15,
                      onTap: () => setDialogState(() => selectedDays = 15),
                    ),
                    _DayChoiceChip(
                      label: 'Last 30 Days',
                      isSelected: selectedDays == 30,
                      onTap: () => setDialogState(() => selectedDays = 30),
                    ),
                    _DayChoiceChip(
                      label: 'Last 60 Days',
                      isSelected: selectedDays == 60,
                      onTap: () => setDialogState(() => selectedDays = 60),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFF38BDF8), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sends a silent background sync command to the child phone. Past conversations will be retrieved and archived.',
                          style: TextStyle(color: const Color(0xFF94A3B8), fontSize: 10, height: 1.3),
                        ),
                      ),
                    ],
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  provider.fetchHistoricalChatsFromDevice(selectedDays);
                  if (selectedDays > 2) {
                    provider.setSelectedChatRange(
                      selectedDays <= 7
                          ? ChatDateRange.last7Days
                          : ChatDateRange.last30Days,
                    );
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Deep historical scan command dispatched for past $selectedDays days!'),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                },
                child: const Text('Fetch & Sync', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openFullScreenPhotoViewer(
    BuildContext context,
    String imageUrl, {
    String? title,
    String? subtitle,
    String? ocrText,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.95),
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.black.withValues(alpha: 0.7),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 24),
            onPressed: () => Navigator.pop(ctx),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title ?? 'Captured Snap / Screenshot',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5.0,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
                        );
                      },
                      errorBuilder: (_, __, ___) => const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image, color: Colors.white60, size: 48),
                            SizedBox(height: 12),
                            Text(
                              'Media expired or unavailable in cloud vault',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (ocrText != null && ocrText.isNotEmpty && !ocrText.startsWith('📷'))
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    border: Border(top: BorderSide(color: Color(0xFF334155))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.text_snippet_outlined, color: Color(0xFF38BDF8), size: 14),
                          SizedBox(width: 6),
                          Text(
                            'Captured Text (OCR)',
                            style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ocrText,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _show1ViewVaultGallery(BuildContext context, List<ChatMessage> snaps) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE1306C).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome, color: Color(0xFFF43F5E), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '📸 1-View Snaps & Media Vault',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${snaps.length} self-destructing snaps captured • Zero alert sent to chat',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF334155), height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: snaps.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final snap = snaps[index];
                  final isSentByChild = !snap.isIncoming;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSentByChild
                            ? const Color(0xFF38BDF8).withValues(alpha: 0.4)
                            : const Color(0xFFF43F5E).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isSentByChild ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                              size: 15,
                              color: isSentByChild ? const Color(0xFF38BDF8) : const Color(0xFFF43F5E),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                isSentByChild
                                    ? 'Child Sent 1-View Snap to ${snap.contactName}'
                                    : 'Received 1-View Snap from ${snap.contactName}',
                                style: TextStyle(
                                  color: isSentByChild ? const Color(0xFF38BDF8) : const Color(0xFFF43F5E),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              DateFormat('hh:mm a • dd MMM').format(snap.timestamp),
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (snap.mediaUrl != null && snap.mediaUrl!.isNotEmpty)
                          GestureDetector(
                            onTap: () => _openFullScreenPhotoViewer(
                              context,
                              snap.mediaUrl!,
                              title: snap.contactName,
                              subtitle: DateFormat('hh:mm a • dd MMM yyyy').format(snap.timestamp),
                              ocrText: snap.messageText,
                            ),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    snap.mediaUrl!,
                                    height: 220,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      height: 120,
                                      color: const Color(0xFF0F172A),
                                      child: const Center(
                                        child: Icon(Icons.broken_image, color: Color(0xFF64748B), size: 36),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.75),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white24, width: 0.8),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.zoom_in_rounded, color: Color(0xFF38BDF8), size: 14),
                                        SizedBox(width: 4),
                                        Text(
                                          'Tap to expand',
                                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            height: 80,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.photo_camera_back_outlined, color: Color(0xFF38BDF8), size: 24),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      snap.messageText.isNotEmpty ? snap.messageText : '1-View Snap Frame Saved',
                                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (snap.messageText.isNotEmpty && !snap.messageText.startsWith('📷')) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.document_scanner_outlined, color: Color(0xFFF59E0B), size: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'OCR Text: ${snap.messageText}',
                                    style: const TextStyle(color: Color(0xFFFCD34D), fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayChoiceChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DayChoiceChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _ConversationThreadCard extends StatelessWidget {
  final ChatConversation conversation;
  final VoidCallback onTap;

  const _ConversationThreadCard({
    required this.conversation,
    required this.onTap,
  });

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

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    if (time.year == now.year && time.month == now.month && time.day == now.day) {
      return DateFormat('hh:mm a').format(time);
    } else if (now.difference(time).inDays < 7) {
      return DateFormat('EEE').format(time);
    } else {
      return DateFormat('dd/MM').format(time);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ParentDashboardProvider>();
    final lastMsg = conversation.lastMessage;
    final appColor = _getAppColor(conversation.appType);
    final isWatchlist = conversation.isWatchlistTarget;
    final relatedCalls = provider.getCallRecordsForContact(
      conversation.contactName,
      conversation.contactIdentifier,
    );
    final relatedCallsCount = relatedCalls.length;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isWatchlist
              ? Colors.redAccent.withValues(alpha: 0.6)
              : const Color(0xFF334155),
          width: isWatchlist ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Avatar / DP with App Icon badge
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: isWatchlist
                          ? Colors.redAccent.withValues(alpha: 0.2)
                          : appColor.withValues(alpha: 0.18),
                      child: Text(
                        conversation.contactName.isNotEmpty
                            ? conversation.contactName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: isWatchlist ? Colors.redAccent : appColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0F172A),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          conversation.appType.iconAsset,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),

                // Name & Last Message snippet
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              conversation.contactName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isWatchlist) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(4),
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
                      const SizedBox(height: 3),
                      // Subtitle / preview
                      if (lastMsg.isDeletedBackup)
                        Row(
                          children: [
                            const Icon(Icons.history_toggle_off, size: 13, color: Color(0xFFFB7185)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '[Deleted]: ${lastMsg.messageText}',
                                style: const TextStyle(
                                  color: Color(0xFFFB7185),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        )
                      else if (!lastMsg.isIncoming)
                        Row(
                          children: [
                            const Icon(Icons.done_all, size: 14, color: Color(0xFF38BDF8)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'You: ${lastMsg.messageText}',
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          lastMsg.messageText,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Trailing: Time + Message count pill + Chevron
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatTime(lastMsg.timestamp),
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (relatedCallsCount > 0) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.phone_in_talk, size: 10, color: Color(0xFF34D399)),
                                const SizedBox(width: 3),
                                Text(
                                  '$relatedCallsCount',
                                  style: const TextStyle(
                                    color: Color(0xFF34D399),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Text(
                            '${conversation.totalMessages}',
                            style: TextStyle(
                              color: appColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right, color: Color(0xFF64748B), size: 16),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OneViewMediaVaultCard extends StatelessWidget {
  final List<ChatMessage> items;
  final VoidCallback onTap;

  const _OneViewMediaVaultCard({
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E293B),
            const Color(0xFF3B0764).withValues(alpha: 0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5), width: 1.2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('📸', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '1-View Snaps & Media Vault',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${items.length}',
                              style: const TextStyle(
                                color: Color(0xFFC4B5FD),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Captured self-destructing snaps preserved with OCR',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF8B5CF6), size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

