import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/theme/theme_mode_provider.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';

class DashboardShell extends ConsumerWidget {
  const DashboardShell({required this.title, required this.body, super.key});

  final String title;
  final Widget body;

  int _calculateSelectedIndex(String currentPath) {
    if (currentPath == '/about') return 2;
    if (currentPath == '/profile') return 3;
    if (currentPath == '/functions' ||
        currentPath.startsWith('/admin/approvals') ||
        currentPath.startsWith('/admin/teachers') ||
        currentPath.startsWith('/admin/classes') ||
        currentPath.startsWith('/admin/audit-logs') ||
        currentPath.startsWith('/admin/schools') ||
        currentPath.startsWith('/teacher/quizzes/new') ||
        currentPath.startsWith('/teacher/results') ||
        currentPath.startsWith('/teacher/students') ||
        currentPath.startsWith('/teacher/reset-passwords')) {
      return 1;
    }
    // Default to Home (0)
    return 0;
  }

  void _onItemTapped(BuildContext context, int index, String? role) {
    switch (index) {
      case 0:
        final homePath = switch (role) {
          AppRoles.admin => '/admin/dashboard',
          AppRoles.teacher => '/teacher/dashboard',
          _ => '/student/dashboard',
        };
        context.go(homePath);
        break;
      case 1:
        context.go('/functions');
        break;
      case 2:
        context.go('/about');
        break;
      case 3:
        context.go('/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final currentPath = GoRouterState.of(context).uri.path;
    final selectedIndex = _calculateSelectedIndex(currentPath);

    final displayName = user?.fullName?.trim().isNotEmpty == true
        ? user!.fullName!.trim()
        : user?.username ?? 'Account';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.school_rounded,
                    size: 18,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  letterSpacing: -0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
            onPressed: () {
              final newMode = isDark ? ThemeMode.light : ThemeMode.dark;
              ref.read(themeModeProvider.notifier).setMode(newMode);
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(isDark ? 'Switched to Light mode' : 'Switched to Dark mode'),
                    ],
                  ),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                  width: 250,
                ),
              );
            },
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: 'My Profile',
            onPressed: () => context.go('/profile'),
            icon: CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
              backgroundImage: user?.avatarUrl == null
                  ? null
                  : NetworkImage(user!.avatarUrl!),
              child: user?.avatarUrl == null
                  ? Text(
                      displayName.isEmpty
                          ? '?'
                          : displayName.characters.first.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    )
                  : null,
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: const Row(
                    children: [
                      Icon(Icons.logout_rounded, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Sign Out'),
                    ],
                  ),
                  content: const Text(
                    'Are you sure you want to sign out of your account on this device?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref.read(authStateProvider.notifier).signOut();
              }
            },
            icon: const Icon(Icons.logout_rounded, size: 20),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // NO menubar / drawer here! Replaced by modern bottom dock:
      drawer: null,
      body: user?.isPendingApproval == true || user?.isRejected == true
          ? Column(
              children: [
                MaterialBanner(
                  leading: Icon(
                    user?.isRejected == true
                        ? Icons.info_outline
                        : Icons.hourglass_top_outlined,
                    color: const Color(0xFF10B981),
                  ),
                  content: Text(
                    user?.isRejected == true
                        ? 'Your access request was declined. Please contact your school administration.'
                        : 'Your registration is pending review by your school administrator.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => context.go('/profile'),
                      child: const Text('Profile'),
                    ),
                  ],
                ),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              width: 1.0,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _BottomNavIcon(
                  label: 'Home',
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home_rounded,
                  isSelected: selectedIndex == 0,
                  onTap: () => _onItemTapped(context, 0, user?.role),
                  isDark: isDark,
                ),
                _BottomNavIcon(
                  label: 'Functions',
                  icon: Icons.grid_view_outlined,
                  selectedIcon: Icons.grid_view_rounded,
                  isSelected: selectedIndex == 1,
                  onTap: () => _onItemTapped(context, 1, user?.role),
                  isDark: isDark,
                ),
                _BottomNavIcon(
                  label: 'About',
                  icon: Icons.info_outline_rounded,
                  selectedIcon: Icons.info_rounded,
                  isSelected: selectedIndex == 2,
                  onTap: () => _onItemTapped(context, 2, user?.role),
                  isDark: isDark,
                ),
                _BottomNavIcon(
                  label: 'Profile',
                  icon: Icons.person_outline_rounded,
                  selectedIcon: Icons.person_rounded,
                  isSelected: selectedIndex == 3,
                  onTap: () => _onItemTapped(context, 3, user?.role),
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavIcon extends StatelessWidget {
  const _BottomNavIcon({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF10B981);
    final inactiveColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? const Color(0xFF064E3B).withValues(alpha: 0.4)
                  : const Color(0xFFECFDF5))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              size: 22,
              color: isSelected ? activeColor : inactiveColor,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? activeColor : inactiveColor,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
