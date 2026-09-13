import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/parent_dashboard_provider.dart';
import '../models/chat_message.dart';
import '../widgets/chat_bubble.dart';

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

    final filteredMessages = provider.chatMessages.where((msg) {
      final matchesApp = msg.appType == selectedApp;
      final matchesSearch = _searchQuery.isEmpty ||
          msg.messageText.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          msg.contactName.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesApp && matchesSearch;
    }).toList();

    final totalAppArchived = provider.allArchivedChatMessages
        .where((m) => m.appType == selectedApp)
        .length;

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
                      'Showing: ${selectedRange.label} (${filteredMessages.length} messages)',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      totalAppArchived > filteredMessages.length
                          ? '${totalAppArchived - filteredMessages.length} older messages available in deep vault'
                          : 'All captured records displayed',
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

          // Chat Feed
          Expanded(
            child: filteredMessages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chat_bubble_outline, color: Color(0xFF64748B), size: 40),
                        const SizedBox(height: 12),
                        Text(
                          'No messages found within ${selectedRange.label}.',
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => provider.setSelectedChatRange(ChatDateRange.allTime),
                          child: const Text('Switch to "All Time" View', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: filteredMessages.length,
                    itemBuilder: (context, index) {
                      final msg = filteredMessages[index];
                      return ChatBubble(message: msg);
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
