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

    final filteredMessages = provider.chatMessages.where((msg) {
      final matchesApp = msg.appType == selectedApp;
      final matchesSearch = _searchQuery.isEmpty ||
          msg.messageText.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          msg.contactName.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesApp && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Monitored Chats & SMS',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

          const Divider(color: Color(0xFF334155), height: 1),

          // Chat Feed
          Expanded(
            child: filteredMessages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages recorded for this app yet.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
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
}
