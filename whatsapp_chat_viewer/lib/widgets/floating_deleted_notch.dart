import 'package:flutter/material.dart';

class FloatingDeletedNotch extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const FloatingDeletedNotch({
    super.key,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();

    return Positioned(
      right: 0,
      top: MediaQuery.of(context).size.height * 0.42,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF991B1B).withValues(alpha: 0.95), // Deep crimson
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              bottomLeft: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(-2, 2),
              ),
            ],
            border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block_flipped, color: Colors.white, size: 16),
              const SizedBox(width: 5),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DELETED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    '$count msgs',
                    style: const TextStyle(
                      color: Color(0xFFFCA5A5),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_left, color: Colors.white, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
