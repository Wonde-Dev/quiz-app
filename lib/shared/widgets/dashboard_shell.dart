import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/theme/theme_mode_provider.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';

class DashboardShell extends ConsumerWidget {
  const DashboardShell({required this.title, required this.body, super.key});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final currentPath = GoRouterState.of(context).uri.path;
    final displayName = user?.fullName?.trim().isNotEmpty == true
        ? user!.fullName!.trim()
        : user?.username ?? 'Your account';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Activity',
            onPressed: () => context.go('/activity'),
            icon: const Icon(Icons.insights_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account menu',
            onSelected: (action) {
              switch (action) {
                case 'profile':
                  context.go('/profile');
                  break;
                case 'theme':
                  ref.read(themeModeProvider.notifier).cycle();
                  break;
                case 'logout':
                  ref.read(authStateProvider.notifier).signOut();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(displayName),
                  subtitle: Text(user?.email ?? ''),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'theme',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.contrast_outlined),
                  title: Text('Cycle theme'),
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout),
                  title: Text('Sign out'),
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CircleAvatar(
                radius: 17,
                backgroundImage: user?.avatarUrl == null
                    ? null
                    : NetworkImage(user!.avatarUrl!),
                child: user?.avatarUrl == null
                    ? Text(
                        displayName.isEmpty
                            ? '?'
                            : displayName.characters.first.toUpperCase(),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              UserAccountsDrawerHeader(
                accountName: Text(displayName),
                accountEmail: Text(user?.email ?? ''),
                currentAccountPicture: CircleAvatar(
                  backgroundImage: user?.avatarUrl == null
                      ? null
                      : NetworkImage(user!.avatarUrl!),
                  child: user?.avatarUrl == null
                      ? Text(
                          displayName.isEmpty
                              ? '?'
                              : displayName.characters.first.toUpperCase(),
                        )
                      : null,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              _NavigationItem(
                icon: Icons.home_outlined,
                label: 'Home',
                selected: currentPath.endsWith('/dashboard'),
                onTap: () => _navigateHome(context, user?.role),
              ),
              _NavigationItem(
                icon: Icons.insights_outlined,
                label: 'Activity',
                selected: currentPath == '/activity',
                onTap: () => context.go('/activity'),
              ),
              _NavigationItem(
                icon: Icons.person_outline,
                label: 'My profile',
                selected: currentPath == '/profile',
                onTap: () => context.go('/profile'),
              ),
              if (user?.isAdmin == true) ...[
                const Divider(),
                _NavigationItem(
                  icon: Icons.verified_user_outlined,
                  label: 'Role requests',
                  selected: currentPath == '/admin/approvals',
                  onTap: () => context.go('/admin/approvals'),
                ),
                _NavigationItem(
                  icon: Icons.quiz_outlined,
                  label: 'Create a quiz',
                  selected: currentPath == '/teacher/quizzes/new',
                  onTap: () => context.push('/teacher/quizzes/new'),
                ),
                _NavigationItem(
                  icon: Icons.people_outline,
                  label: 'Manage students',
                  selected: currentPath == '/teacher/students',
                  onTap: () => context.push('/teacher/students'),
                ),
                _NavigationItem(
                  icon: Icons.class_outlined,
                  label: 'Classes and teacher assignments',
                  selected: currentPath == '/admin/classes',
                  onTap: () => context.go('/admin/classes'),
                ),
              ] else if (user?.isTeacher == true) ...[
                const Divider(),
                _NavigationItem(
                  icon: Icons.quiz_outlined,
                  label: 'Create a quiz',
                  selected: currentPath == '/teacher/quizzes/new',
                  onTap: () => context.push('/teacher/quizzes/new'),
                ),
                _NavigationItem(
                  icon: Icons.people_outline,
                  label: 'Manage students',
                  selected: currentPath == '/teacher/students',
                  onTap: () => context.push('/teacher/students'),
                ),
              ],
              const Spacer(),
              const Divider(),
              _NavigationItem(
                icon: Theme.of(context).brightness == Brightness.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                label: 'Cycle theme',
                onTap: () => ref.read(themeModeProvider.notifier).cycle(),
              ),
              _NavigationItem(
                icon: Icons.logout,
                label: 'Sign out',
                onTap: () => ref.read(authStateProvider.notifier).signOut(),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      body: user?.isPendingApproval == true || user?.isRejected == true
          ? Column(
              children: [
                MaterialBanner(
                  leading: Icon(
                    user?.isRejected == true
                        ? Icons.info_outline
                        : Icons.hourglass_top_outlined,
                  ),
                  content: Text(
                    user?.isRejected == true
                        ? 'Your request for ${user?.requestedRole == 'admin' ? 'administrator' : 'teacher'} access was declined. You can continue using your student account.'
                        : 'You’re using student access while your '
                              '${user?.requestedRole == 'admin' ? 'administrator' : 'teacher'} '
                              'request is reviewed. Sign out and back in after approval to refresh access.',
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
    );
  }

  void _navigateHome(BuildContext context, String? role) {
    final path = switch (role) {
      'admin' => '/admin/dashboard',
      'teacher' => '/teacher/dashboard',
      _ => '/student/dashboard',
    };
    context.go(path);
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      leading: Icon(icon),
      title: Text(label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
    );
  }
}
