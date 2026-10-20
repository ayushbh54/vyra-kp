import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/parent_dashboard_provider.dart';

class NotificationsFeedScreen extends StatefulWidget {
  const NotificationsFeedScreen({super.key});

  @override
  State<NotificationsFeedScreen> createState() => _NotificationsFeedScreenState();
}

class _NotificationsFeedScreenState extends State<NotificationsFeedScreen> {
  String _selectedPackage = 'ALL';
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ParentDashboardProvider>();
    final allNotifications = provider.notifications;

    // Distinct packages for filter chips
    final packageList = ['ALL', ...allNotifications.map((n) => n.appName).toSet()];

    final filtered = allNotifications.where((n) {
      final matchesApp = _selectedPackage == 'ALL' || n.appName == _selectedPackage;
      final matchesSearch = _searchQuery.isEmpty ||
          n.message.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          n.title.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesApp && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Notification Logs',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
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
                hintText: 'Search notification logs...',
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

          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: packageList.map((app) {
                final isSelected = app == _selectedPackage;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    selected: isSelected,
                    showCheckmark: false,
                    label: Text(
                      app,
                      style: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                    backgroundColor: const Color(0xFF1E293B),
                    selectedColor: const Color(0xFF3B82F6),
                    side: BorderSide(
                      color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF334155),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    onSelected: (_) => setState(() => _selectedPackage = app),
                  ),
                );
              }).toList(),
            ),
          ),

          const Divider(color: Color(0xFF334155), height: 1),

          // Notifications List
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF38BDF8),
              backgroundColor: const Color(0xFF1E293B),
              onRefresh: () => context.read<ParentDashboardProvider>().refreshAll(forceFull: true),
              child: filtered.isEmpty
                  ? const SingleChildScrollView(
                      physics: AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: 400,
                        child: Center(
                          child: Text(
                            'No matching notifications found.\nNeeche pull karke refresh karo.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final timeStr = DateFormat('hh:mm a • dd MMM').format(item.timestamp);

                        return Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: item.isSensitiveAlert
                                ? Colors.redAccent.withValues(alpha: 0.6)
                                : const Color(0xFF334155),
                            width: item.isSensitiveAlert ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            item.appName,
                                            style: const TextStyle(
                                              color: Color(0xFF38BDF8),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ),
                                      if (item.isDeletedBackup) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.pink.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'PRESERVED',
                                            style: TextStyle(color: Colors.pinkAccent, fontSize: 9, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  timeStr,
                                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (item.title.isNotEmpty)
                              Text(
                                item.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            const SizedBox(height: 2),
                            Text(
                              item.message,
                              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            ),  // RefreshIndicator
          ),    // Expanded
        ],
      ),
    );
  }
}
