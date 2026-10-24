import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _imagePicker = ImagePicker();
  String? _loadedUserId;
  String? _feedback;
  String? _passwordFeedback;
  bool _saved = false;
  bool _passwordSaved = false;
  bool _savingPassword = false;

  @override
  void dispose() {
    _nameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _feedback = null;
      _saved = false;
    });
    try {
      await ref
          .read(authStateProvider.notifier)
          .saveFullName(_nameController.text);
      if (mounted) setState(() => _saved = true);
    } catch (error) {
      if (mounted) setState(() => _feedback = error.toString());
    }
  }

  Future<void> _pickProfilePhoto() async {
    if (mounted) {
      setState(() {
        _feedback = null;
        _saved = false;
      });
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Profile Picture',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take Photo with Camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 90,
      );
      if (image == null) return;
      await ref.read(authStateProvider.notifier).saveAvatar(image);
      if (mounted) setState(() => _saved = true);
    } catch (error) {
      if (mounted) setState(() => _feedback = error.toString());
    }
  }

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    setState(() {
      _savingPassword = true;
      _passwordFeedback = null;
      _passwordSaved = false;
    });
    try {
      await ref
          .read(authStateProvider.notifier)
          .changeOwnPassword(
            currentPassword: _currentPasswordController.text,
            newPassword: _newPasswordController.text,
          );
      final successMessage =
          ref.read(authStateProvider).successMessage ??
          'Password changed successfully.';
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (mounted) {
        setState(() {
          _passwordSaved = true;
          _passwordFeedback = successMessage;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _passwordFeedback = error.toString());
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadedUserId != user.id) {
      _loadedUserId = user.id;
      _nameController.text = user.fullName ?? '';
    }

    final displayName = user.fullName?.trim().isNotEmpty == true
        ? user.fullName!.trim()
        : user.username;
    final initial = displayName.isEmpty
        ? '?'
        : displayName.characters.first.toUpperCase();
    final role = user.isRejected
        ? 'Student · ${user.requestedRole} request declined'
        : user.isPendingApproval && user.requestedRole != null
        ? 'Student · ${user.requestedRole} access requested'
        : user.role[0].toUpperCase() + user.role.substring(1);

    final resolvedAvatar = user.avatarUrl == null || user.avatarUrl!.isEmpty
        ? null
        : (user.avatarUrl!.startsWith('http://') || user.avatarUrl!.startsWith('https://'))
            ? user.avatarUrl
            : Supabase.instance.client.storage
                .from('profile-photos')
                .getPublicUrl(user.avatarUrl!);

    return DashboardShell(
      title: 'My profile',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 38,
                              backgroundImage: resolvedAvatar == null
                                  ? null
                                  : NetworkImage(resolvedAvatar),
                              onBackgroundImageError: resolvedAvatar == null
                                  ? null
                                  : (_, _) {},
                              child: resolvedAvatar == null
                                  ? Text(
                                      initial,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium,
                                    )
                                  : null,
                            ),
                            TextButton.icon(
                              onPressed: authState.isLoading
                                  ? null
                                  : _pickProfilePhoto,
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Change profile photo'),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              displayName,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(user.email),
                            const SizedBox(height: 8),
                            Chip(
                              avatar: const Icon(
                                Icons.verified_user_outlined,
                                size: 18,
                              ),
                              label: Text(role),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 36),
                      Text(
                        'Profile details',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      Form(
                        key: _formKey,
                        child: TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          textCapitalization: TextCapitalization.words,
                          validator: (value) =>
                              value == null || value.trim().length < 2
                              ? 'Enter your name'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: user.username,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      if (_feedback != null || _saved) ...[
                        const SizedBox(height: 12),
                        Text(
                          _saved ? 'Profile saved.' : _feedback!,
                          style: TextStyle(
                            color: _saved
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: authState.isLoading ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          authState.isLoading ? 'Saving…' : 'Save profile',
                        ),
                      ),
                      const Divider(height: 40),
                      Text(
                        'Account security',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Change your password. We’ll verify your current password first.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      Form(
                        key: _passwordFormKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _currentPasswordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Current password',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              validator: (value) =>
                                  value == null || value.isEmpty
                                  ? 'Enter your current password'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _newPasswordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'New password',
                                prefixIcon: Icon(Icons.lock_reset_outlined),
                              ),
                              validator: (value) =>
                                  value == null || value.length < 8
                                  ? 'Use at least 8 characters'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Confirm new password',
                                prefixIcon: Icon(Icons.verified_user_outlined),
                              ),
                              validator: (value) =>
                                  value != _newPasswordController.text
                                  ? 'Passwords do not match'
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      if (_passwordFeedback != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _passwordFeedback!,
                          style: TextStyle(
                            color: _passwordSaved
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _savingPassword ? null : _changePassword,
                        icon: _savingPassword
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.password_outlined),
                        label: Text(
                          _savingPassword
                              ? 'Changing password…'
                              : 'Change password',
                        ),
                      ),
                      const Divider(height: 40),
                      Text(
                        'Account session',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sign out of your account on this device. You will need your login credentials to sign back in.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                          side: BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .error
                                .withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
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
                                'Are you sure you want to sign out of Ciro High Schools portal?',
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
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Sign Out of Account'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
