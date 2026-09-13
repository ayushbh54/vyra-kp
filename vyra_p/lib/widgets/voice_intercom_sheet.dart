import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/parent_dashboard_provider.dart';

class VoiceIntercomSheet extends StatefulWidget {
  const VoiceIntercomSheet({super.key});

  @override
  State<VoiceIntercomSheet> createState() => _VoiceIntercomSheetState();
}

class _VoiceIntercomSheetState extends State<VoiceIntercomSheet> {
  bool _isSpeaking = false;
  final TextEditingController _customTextCtrl = TextEditingController();

  final List<String> _voicePresets = [
    "Beta, phone band karo aur dinner ke liye aao!",
    "Coaching ka time ho gaya hai, turant niklo.",
    "Raat ke 10 baj gaye hain, phone table par rakh do.",
    "Papa room me aa rahe hain, padhai start karo.",
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ParentDashboardProvider>();
    final activeChild = provider.activeChild;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF475569),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.record_voice_over, color: Color(0xFF10B981), size: 24),
                const SizedBox(width: 8),
                Text(
                  'Live Voice Intercom • ${activeChild.name}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Your voice will play out loud through the child\'s phone loudspeaker.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Big Push-To-Talk Mic Button
            GestureDetector(
              onTapDown: (_) {
                setState(() => _isSpeaking = true);
              },
              onTapUp: (_) {
                setState(() => _isSpeaking = false);
                provider.sendVoiceIntercom("Parent live voice announcement sent");
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Voice broadcast played on ${activeChild.name}\'s phone!'),
                    backgroundColor: const Color(0xFF10B981),
                  ),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _isSpeaking ? 110 : 96,
                height: _isSpeaking ? 110 : 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isSpeaking ? Colors.redAccent : const Color(0xFF10B981),
                  boxShadow: [
                    BoxShadow(
                      color: (_isSpeaking ? Colors.redAccent : const Color(0xFF10B981)).withValues(alpha: 0.4),
                      blurRadius: _isSpeaking ? 24 : 12,
                      spreadRadius: _isSpeaking ? 8 : 2,
                    ),
                  ],
                ),
                child: Icon(
                  _isSpeaking ? Icons.mic : Icons.mic_none,
                  color: Colors.white,
                  size: 42,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isSpeaking ? 'RECORDING & BROADCASTING...' : 'HOLD TO SPEAK LIVE',
              style: TextStyle(
                color: _isSpeaking ? Colors.redAccent : const Color(0xFF38BDF8),
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),

            const SizedBox(height: 28),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Quick Voice Announcements (1-Tap Blast)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            const SizedBox(height: 10),

            // Quick Voice Presets
            ..._voicePresets.map((preset) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    side: const BorderSide(color: Color(0xFF334155)),
                    backgroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    provider.sendVoiceIntercom(preset);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Announcement sent to ${activeChild.name}\'s speaker: "$preset"'),
                        backgroundColor: const Color(0xFF10B981),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.volume_up, color: Color(0xFF38BDF8), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          preset,
                          style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12),
                        ),
                      ),
                      const Icon(Icons.send_rounded, color: Color(0xFF10B981), size: 16),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 12),

            // Custom Text-To-Speech Input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customTextCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Type custom voice announcement...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFF1E88E5)),
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: () {
                    if (_customTextCtrl.text.trim().isNotEmpty) {
                      provider.sendVoiceIntercom(_customTextCtrl.text.trim());
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Broadcast sent: "${_customTextCtrl.text.trim()}"'),
                          backgroundColor: const Color(0xFF10B981),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
