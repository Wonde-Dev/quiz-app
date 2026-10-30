import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/utils/validators.dart';
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
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
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
    _emailController.dispose();
    _phoneController.dispose();
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
      await ref.read(authStateProvider.notifier).saveProfileDetails(
            fullName: _nameController.text.trim(),
            email: _emailController.text.trim(),
            phoneNumber: _phoneController.text.trim(),
          );
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
      await ref.read(authStateProvider.notifier).changeOwnPassword(
            currentPassword: _currentPasswordController.text,
            newPassword: _newPasswordController.text,
          );
      final successMessage = ref.read(authStateProvider).successMessage ??
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
      _emailController.text = user.email;
      _phoneController.text = user.phoneNumber ?? '';
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
            : (user.role == 'subadmin' || user.role == 'director')
                ? 'School Director'
                : user.role == 'admin'
                    ? 'System Administrator'
                    : user.role[0].toUpperCase() + user.role.substring(1);

    final resolvedAvatar = user.avatarUrl == null || user.avatarUrl!.isEmpty
        ? null
        : (user.avatarUrl!.startsWith('http://') ||
                user.avatarUrl!.startsWith('https://'))
            ? user.avatarUrl
            : Supabase.instance.client.storage
                .from('profile-photos')
                .getPublicUrl(user.avatarUrl!);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DashboardShell(
      title: 'My Profile & Portfolio',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shrinkWrap: true,
            children: [
              // Profile Hero Banner with Profile Illustration
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFF10B981).withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.16),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.4)
                          : const Color(0xFF0F172A).withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Illustration Backdrop
                    Positioned.fill(
                      child: Image.asset(
                        'assets/images/profile.jpeg',
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: const Color(0xFF064E3B),
                        ),
                      ),
                    ),
                    // Luxury Gradient Tint
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: isDark
                                ? [
                                    const Color(0xF2064E3B),
                                    const Color(0xF80F172A),
                                  ]
                                : [
                                    const Color(0xEE064E3B),
                                    const Color(0xEB0F172A),
                                  ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 28),
                      child: Center(
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF10B981),
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981)
                                        .withValues(alpha: 0.4),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 46,
                                backgroundColor: Colors.white,
                                backgroundImage: resolvedAvatar == null
                                    ? null
                                    : NetworkImage(resolvedAvatar),
                                onBackgroundImageError: resolvedAvatar == null
                                    ? null
                                    : (_, _) {},
                                child: resolvedAvatar == null
                                    ? Text(
                                        initial,
                                        style: const TextStyle(
                                          fontSize: 36,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF10B981),
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.2),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              onPressed: authState.isLoading
                                  ? null
                                  : _pickProfilePhoto,
                              icon: const Icon(Icons.photo_camera_outlined,
                                  size: 16),
                              label: const Text(
                                'Change Profile Photo',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.alternate_email_rounded,
                                      size: 14,
                                      color: Color(0xFFCBD5E1),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      user.email,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFFCBD5E1),
                                      ),
                                    ),
                                  ],
                                ),
                                if (user.phoneNumber != null &&
                                    user.phoneNumber!.isNotEmpty)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.phone_outlined,
                                        size: 14,
                                        color: Color(0xFF34D399),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        user.phoneNumber!,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF34D399),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.verified_user_rounded,
                                    size: 15,
                                    color: Color(0xFF34D399),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    role,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Portfolio Information Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.badge_rounded,
                              color: Color(0xFF10B981),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Personal Portfolio & Contact',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Update your full name, email address, and active phone number.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: 'Full Name',
                                hintText: 'e.g. John Doe',
                                prefixIcon:
                                    const Icon(Icons.person_outline_rounded),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              textCapitalization: TextCapitalization.words,
                              validator: (value) =>
                                  value == null || value.trim().length < 2
                                      ? 'Enter your full name'
                                      : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              initialValue: user.username,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Institutional Username (Permanent)',
                                helperText:
                                    'Assigned institutional login identity',
                                prefixIcon: const Icon(
                                    Icons.alternate_email_rounded,
                                    color: Color(0xFF10B981)),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF1E293B)
                                    : const Color(0xFFF8FAFC),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: 'Email Address',
                                hintText: 'name@ciroschool.edu',
                                prefixIcon:
                                    const Icon(Icons.mail_outline_rounded),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: Validators.email,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'Phone Number',
                                hintText: '+251 91 123 4567 or 0911234567',
                                prefixIcon:
                                    const Icon(Icons.phone_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: Validators.phone,
                            ),
                          ],
                        ),
                      ),
                      if (_feedback != null || _saved) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: _saved
                                ? const Color(0xFF10B981).withValues(alpha: 0.1)
                                : Theme.of(context)
                                    .colorScheme
                                    .error
                                    .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _saved
                                  ? const Color(0xFF10B981)
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _saved
                                    ? Icons.check_circle_rounded
                                    : Icons.error_outline_rounded,
                                size: 18,
                                color: _saved
                                    ? const Color(0xFF10B981)
                                    : Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _saved
                                      ? 'Portfolio profile details saved successfully.'
                                      : _feedback!,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: _saved
                                        ? const Color(0xFF10B981)
                                        : Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 2,
                        ),
                        onPressed: authState.isLoading ? null : _save,
                        icon: authState.isLoading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline_rounded,
                                size: 20),
                        label: Text(
                          authState.isLoading
                              ? 'Saving Changes…'
                              : 'Save Portfolio Details',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const Divider(height: 48),

                      // Account Security Section
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.security_rounded,
                              color: Color(0xFF6366F1),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Account Security',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Change your password. We will verify your current credentials first.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Form(
                        key: _passwordFormKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _currentPasswordController,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'Current Password',
                                prefixIcon:
                                    const Icon(Icons.lock_outline_rounded),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (value) =>
                                  value == null || value.isEmpty
                                      ? 'Enter your current password'
                                      : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _newPasswordController,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'New Password',
                                prefixIcon: const Icon(
                                    Icons.lock_reset_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (value) =>
                                  value == null || value.length < 8
                                      ? 'Use at least 8 characters'
                                      : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'Confirm New Password',
                                prefixIcon: const Icon(
                                    Icons.verified_user_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
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
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: _passwordSaved
                                ? const Color(0xFF10B981).withValues(alpha: 0.1)
                                : Theme.of(context)
                                    .colorScheme
                                    .error
                                    .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _passwordSaved
                                  ? const Color(0xFF10B981)
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                          child: Text(
                            _passwordFeedback!,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _passwordSaved
                                  ? const Color(0xFF10B981)
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _savingPassword ? null : _changePassword,
                        icon: _savingPassword
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.password_rounded),
                        label: Text(
                          _savingPassword
                              ? 'Changing Password…'
                              : 'Change Password',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Divider(height: 48),

                      // Sign Out Section
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.logout_rounded,
                              color: Colors.red,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sign Out of Account',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Sign out on this device. You will need your credentials or OTP to sign back in.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(
                            color: Colors.red.withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 13,
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
                                'Are you sure you want to sign out of Ciro High School portal?',
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
                            await ref
                                .read(authStateProvider.notifier)
                                .signOut();
                          }
                        },
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text(
                          'Sign Out of Portal',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
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
