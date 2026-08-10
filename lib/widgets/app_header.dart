import 'package:flutter/material.dart';

class AppHeader extends StatelessWidget {
  final int totalBases;

  const AppHeader({
    super.key,
    required this.totalBases,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                'assets/ic_header_logo.png',
                width: 68,
                height: 68,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFACC15),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF111827),
                    size: 34,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI FIND BASE',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Find Similar Clash of Clans Bases Instantly',
                    style: TextStyle(
                      color: Color(0xFFD1D5DB),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;

  const _Badge({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFACC15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF111827),
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}