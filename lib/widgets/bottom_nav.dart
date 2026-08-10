import 'package:flutter/material.dart';

class BottomNav extends StatelessWidget {
  final VoidCallback? onHome;
  final VoidCallback? onSaved;
  final VoidCallback? onPremium;
  final VoidCallback? onMore;

  const BottomNav({
    super.key,
    this.onHome,
    this.onSaved,
    this.onPremium,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      color: const Color(0xF0111827),
      child: Row(
        children: [
          _NavItem(
            icon: Icons.home_rounded,
            label: 'Home',
            onTap: onHome ?? () {},
          ),
          _NavItem(
            icon: Icons.bookmark_rounded,
            label: 'Saved',
            onTap: onSaved ?? () {},
          ),
          _NavItem(
            icon: Icons.workspace_premium_rounded,
            label: 'Ad-Free',
            gold: true,
            onTap: onPremium ?? () {},
          ),
          _NavItem(
            icon: Icons.menu_rounded,
            label: 'More',
            onTap: onMore ?? () {},
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool gold;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.gold = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = gold ? const Color(0xFFFACC15) : Colors.white;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: color,
              size: 23,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}