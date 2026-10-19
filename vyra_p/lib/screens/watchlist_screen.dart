import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/parent_dashboard_provider.dart';

class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ParentDashboardProvider>();
    final targets = provider.watchlistTargets;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Priority Watchlist',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.redAccent,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Add Target', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () => _showAddTargetDialog(context, provider),
      ),
      body: targets.isEmpty
          ? const Center(
              child: Text(
                'No priority contacts added yet.\nTap below to monitor a suspicious contact.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: targets.length,
              itemBuilder: (context, index) {
                final target = targets[index];
                final lastTime = DateFormat('hh:mm a • dd MMM').format(target.lastInteracted);

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    target.name,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  Text(
                                    target.identifier,
                                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'HIGH ALERT',
                                  style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                tooltip: 'Remove from Watchlist',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _showRemoveTargetDialog(context, provider, target),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Reason / Note: ${target.note}',
                        style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Color(0xFF334155), height: 1),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Calls: ${target.totalCalls}  •  Chats: ${target.totalChats}',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                          ),
                          Text(
                            'Last: $lastTime',
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _showAddTargetDialog(BuildContext context, ParentDashboardProvider provider) {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Add to Watchlist', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Contact / Alias Name',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: idCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Phone Number or @Handle',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Reason / Concern Note',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && idCtrl.text.isNotEmpty) {
                provider.addWatchlistTarget(nameCtrl.text, idCtrl.text, noteCtrl.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add Target', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRemoveTargetDialog(BuildContext context, ParentDashboardProvider provider, dynamic target) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Remove from Watchlist?',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "${target.name}" (${target.identifier}) from your priority watchlist?\n\nYou will no longer receive high-priority alerts when this contact messages or calls.',
          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.delete_forever, color: Colors.white, size: 18),
            label: const Text('Remove Target', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () {
              provider.removeWatchlistTarget(target.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Removed "${target.name}" from priority watchlist.'),
                  backgroundColor: const Color(0xFF1E293B),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 3),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
