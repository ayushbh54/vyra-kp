import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/parent_dashboard_provider.dart';
import '../widgets/audio_player_card.dart';

class CallsScreen extends StatelessWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ParentDashboardProvider>();
    final calls = provider.callRecords;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Call Logs & Recordings',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Color(0xFF94A3B8)),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E293B),
                  title: const Text('Vivo Call Recordings Info', style: TextStyle(color: Colors.white)),
                  content: const Text(
                    'Recordings are automatically captured from the child\'s Vivo T3 Pro native dialer (/Record/Call/) and synced to your parent dashboard.\n\nIf the child attempts to manually tap "Stop Recording", Vyra\'s anti-tamper service auto-resumes the recording and highlights it with a warning badge.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Understood', style: TextStyle(color: Color(0xFF38BDF8))),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF38BDF8),
        backgroundColor: const Color(0xFF1E293B),
        onRefresh: () => context.read<ParentDashboardProvider>().refreshAll(forceFull: true),
        child: calls.isEmpty
            ? const SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: 500,
                  child: Center(
                    child: Text(
                      'No call recordings synced yet.\nNeeche pull karke refresh karo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ),
                ),
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: calls.length,
                itemBuilder: (context, index) {
                  final call = calls[index];
                  final isPlaying = provider.currentlyPlayingAudioId == call.id;

                  return AudioPlayerCard(
                    record: call,
                    isPlaying: isPlaying,
                    onPlayToggle: () => provider.togglePlayAudio(call.id),
                  );
                },
              ),
      ),
    );
  }
}
