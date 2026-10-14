import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/whatsapp_conversation.dart';
import '../models/whatsapp_message.dart';
import '../providers/whatsapp_viewer_provider.dart';
import '../theme/whatsapp_theme.dart';
import '../widgets/floating_deleted_notch.dart';
import 'deleted_chats_drawer.dart';
import 'whatsapp_chat_screen.dart';
import 'whatsapp_import_screen.dart';

class WhatsAppHomeScreen extends StatefulWidget {
  const WhatsAppHomeScreen({super.key});

  @override
  State<WhatsAppHomeScreen> createState() => _WhatsAppHomeScreenState();
}

class _WhatsAppHomeScreenState extends State<WhatsAppHomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _openDeletedNotchSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: const DeletedChatsDrawer(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WhatsAppViewerProvider>();

    // If no database is loaded yet, show dedicated Decrypt & Import Screen
    if (!provider.isLoaded) {
      return const WhatsAppImportScreen();
    }

    final conversations = provider.conversations;
    final deleted = provider.allDeletedMessages;

    return Scaffold(
      backgroundColor: WhatsAppTheme.scaffoldBg,
      appBar: AppBar(
        backgroundColor: WhatsAppTheme.appBarBg,
        elevation: 0,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: WhatsAppTheme.textPrimary, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Search chats or messages...',
                  hintStyle: TextStyle(color: WhatsAppTheme.textSecondary, fontSize: 15),
                  border: InputBorder.none,
                ),
                onChanged: (val) => provider.search(val),
              )
            : const Text(
                'WhatsApp',
                style: TextStyle(
                  color: WhatsAppTheme.textSecondary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: WhatsAppTheme.textSecondary),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  provider.search('');
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: WhatsAppTheme.textSecondary),
            color: WhatsAppTheme.appBarBg,
            onSelected: (val) {
              if (val == 'change_db') {
                provider.clearDatabase();
              } else if (val == 'deleted_notch') {
                _openDeletedNotchSheet(context);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'deleted_notch',
                child: Row(
                  children: [
                    Icon(Icons.block_flipped, color: WhatsAppTheme.deletedColor, size: 18),
                    SizedBox(width: 10),
                    Text('View All Deleted Chats', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'change_db',
                child: Row(
                  children: [
                    Icon(Icons.folder_open, color: WhatsAppTheme.primaryGreen, size: 18),
                    SizedBox(width: 10),
                    Text('Open Another Database', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: WhatsAppTheme.primaryGreen,
          labelColor: WhatsAppTheme.primaryGreen,
          unselectedLabelColor: WhatsAppTheme.textSecondary,
          indicatorWeight: 3,
          tabs: [
            Tab(text: 'CHATS (${conversations.length})'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('DELETED'),
                  if (deleted.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: WhatsAppTheme.deletedColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${deleted.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              // 1. CHATS TAB
              conversations.isEmpty
                  ? const Center(
                      child: Text(
                        'No conversations found matching search.',
                        style: TextStyle(color: WhatsAppTheme.textSecondary, fontSize: 14),
                      ),
                    )
                  : ListView.separated(
                      itemCount: conversations.length,
                      separatorBuilder: (context, index) => const Divider(
                        color: WhatsAppTheme.dividerColor,
                        height: 1,
                        indent: 74,
                      ),
                      itemBuilder: (context, index) {
                        final conv = conversations[index];
                        return _buildConversationTile(context, conv);
                      },
                    ),

              // 2. DELETED TAB
              deleted.isEmpty
                  ? const Center(
                      child: Text(
                        'No deleted chats found in this database.',
                        style: TextStyle(color: WhatsAppTheme.textSecondary, fontSize: 14),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: deleted.length,
                      separatorBuilder: (context, index) => const Divider(
                        color: WhatsAppTheme.dividerColor,
                        height: 1,
                        indent: 74,
                      ),
                      itemBuilder: (context, index) {
                        final msg = deleted[index];
                        return _buildDeletedMessageTile(context, msg, conversations);
                      },
                    ),
            ],
          ),

          // FAST ACCESS FLOATING DELETED NOTCH
          FloatingDeletedNotch(
            count: deleted.length,
            onTap: () => _openDeletedNotchSheet(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: WhatsAppTheme.primaryGreen,
        onPressed: () => provider.clearDatabase(),
        tooltip: 'Change / Open New Database',
        child: const Icon(Icons.add, color: Colors.black, size: 28),
      ),
    );
  }

  Widget _buildConversationTile(BuildContext context, WhatsAppConversation conv) {
    final last = conv.lastMessage;
    final timeStr = _formatTimestamp(last.timestamp);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 25,
        backgroundColor: conv.isGroup
            ? WhatsAppTheme.primaryGreen.withValues(alpha: 0.25)
            : WhatsAppTheme.accentBlue.withValues(alpha: 0.25),
        child: Icon(
          conv.isGroup ? Icons.groups_rounded : Icons.person_rounded,
          color: conv.isGroup ? WhatsAppTheme.primaryGreen : WhatsAppTheme.accentBlue,
          size: 26,
        ),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              conv.name,
              style: const TextStyle(
                color: WhatsAppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            timeStr,
            style: TextStyle(
              color: conv.deletedCount > 0 ? WhatsAppTheme.deletedColor : WhatsAppTheme.textSecondary,
              fontSize: 11.5,
              fontWeight: conv.deletedCount > 0 ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            if (last.isFromChild) ...[
              const Icon(Icons.done_all, color: WhatsAppTheme.blueTick, size: 16),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                last.isDeleted ? '🚫 ${last.text}' : last.text,
                style: TextStyle(
                  color: last.isDeleted ? const Color(0xFFFCA5A5) : WhatsAppTheme.textSecondary,
                  fontSize: 13.5,
                  fontStyle: last.isDeleted ? FontStyle.italic : FontStyle.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (conv.deletedCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: WhatsAppTheme.deletedColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${conv.deletedCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
      onTap: () {
        context.read<WhatsAppViewerProvider>().selectConversation(conv);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WhatsAppChatScreen(conversation: conv),
          ),
        );
      },
    );
  }

  Widget _buildDeletedMessageTile(
    BuildContext context,
    WhatsAppMessage msg,
    List<WhatsAppConversation> conversations,
  ) {
    final timeStr = DateFormat('MMM d, h:mm a').format(msg.timestamp);

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: Colors.red.withValues(alpha: 0.2),
        child: const Icon(Icons.block_flipped, color: WhatsAppTheme.deletedColor, size: 22),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              msg.sender.isNotEmpty ? msg.sender : 'Sender',
              style: const TextStyle(
                color: WhatsAppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            timeStr,
            style: const TextStyle(color: WhatsAppTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF2E151B),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF7F1D1D)),
          ),
          child: Text(
            msg.text,
            style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      onTap: () {
        final c = conversations.firstWhere(
          (item) => item.id == msg.threadId || item.name == msg.sender,
          orElse: () => conversations.isNotEmpty
              ? conversations.first
              : WhatsAppConversation(
                  id: msg.threadId,
                  name: msg.sender,
                  isGroup: false,
                ),
        );
        context.read<WhatsAppViewerProvider>().selectConversation(c);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WhatsAppChatScreen(conversation: c),
          ),
        );
      },
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return DateFormat('h:mm a').format(dt);
    }
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day - 1) {
      return 'Yesterday';
    }
    return DateFormat('d/M/yy').format(dt);
  }
}
