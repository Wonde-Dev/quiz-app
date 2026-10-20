import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/theme/theme_mode_provider.dart';
import 'package:quiz_app/core/utils/validators.dart';
import 'package:quiz_app/core/utils/role_username.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({this.registrationPage = false, this.role, super.key});

  final bool registrationPage;
  final String? role;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _subjectController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _schoolsFuture;
  Future<List<Map<String, dynamic>>> _sectionsFuture = Future.value([]);
  String? _selectedSchoolId;
  String? _selectedSectionId;
  String? _selectedSectionGradeName;
  String? _selectedTeacherClassName;
  bool _schoolsReady = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  String _requestedRole = 'student';
  bool get _isRegistering => widget.registrationPage;

  @override
  void initState() {
    super.initState();
    _requestedRole = widget.role == 'teacher' ? 'teacher' : 'student';
    _schoolsFuture = widget.registrationPage
        ? _loadSchools()
        : Future.value([]);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(authStateProvider.notifier);
    if (_isRegistering) {
      final username = _usernameController.text.trim();
      if (!isRoleUsername(username, _requestedRole)) {
        ref
            .read(authStateProvider.notifier)
            .setMessage(
              error:
                  'Use the suggested username ending in @${_requestedRole == 'teacher' ? 'Teacher' : 'Student'}.edu.',
            );
        return;
      }
      await notifier.register(
        fullName: _nameController.text.trim(),
        username: username,
        email: _emailController.text.trim(),
        password: _passwordController.text,
        requestedRole: _requestedRole,
        schoolId: _selectedSchoolId,
        sectionId: _requestedRole == 'student' ? _selectedSectionId : null,
        requestedGrade: _selectedSectionGradeName,
        requestedClass: _requestedRole == 'teacher'
            ? _selectedTeacherClassName
            : null,
        requestedSubject: _requestedRole == 'teacher'
            ? _subjectController.text.trim()
            : null,
      );
    } else {
      await notifier.signIn(
        emailOrUsername: _usernameController.text.trim(),
        password: _passwordController.text,
        expectedRole: roleFromUsername(_usernameController.text.trim()),
      );
    }
  }

  void _navigateToAuthRoute(String path) {
    ref.read(authStateProvider.notifier).clearMessages();
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: widget.registrationPage
            ? IconButton(
                tooltip: 'Back to sign in',
                onPressed: () => _navigateToAuthRoute('/login'),
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Switch theme',
            onPressed: () => ref.read(themeModeProvider.notifier).cycle(),
            icon: Icon(
              theme.brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const _CompactBrand(),
                    const SizedBox(height: 20),
                    const _AnimatedWelcomePanel(compact: true),
                    const SizedBox(height: 20),
                    _formPanel(authState, theme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formPanel(AuthState authState, ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 490),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.registrationPage ? 'Create your account' : 'Sign in',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.registrationPage
                        ? 'Choose a student or teacher account and add your details.'
                        : 'Enter your username and password.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isRegistering) ...[
                        Text(
                          'Your information',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            for (final option in const [
                              (role: 'student', label: 'Student'),
                              (role: 'teacher', label: 'Teacher'),
                            ])
                              ChoiceChip(
                                avatar: Icon(
                                  option.role == 'student'
                                      ? Icons.school_outlined
                                      : Icons.co_present_outlined,
                                  size: 18,
                                ),
                                label: Text(option.label),
                                selected: _requestedRole == option.role,
                                onSelected: (selected) {
                                  if (!selected) return;
                                  setState(() => _requestedRole = option.role);
                                  _updateGeneratedUsername();
                                  ref
                                      .read(authStateProvider.notifier)
                                      .clearMessages();
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _requestedRole == 'teacher'
                              ? 'Teacher access is reviewed by a school administrator.'
                              : 'Student accounts are ready after email verification.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _nameController,
                          onChanged: (_) => _updateGeneratedUsername(),
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          validator: (value) {
                            if (!_isRegistering) return null;
                            if (value == null ||
                                value.trim().split(RegExp(r'\s+')).length < 2) {
                              return 'Enter your first and last name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: _usernameController,
                        autofillHints: _isRegistering
                            ? const [AutofillHints.newUsername]
                            : const [AutofillHints.username],
                        decoration: InputDecoration(
                          labelText: _isRegistering
                              ? 'Suggested username'
                              : 'Username or email',
                          helperText: _isRegistering
                              ? 'Generated from your name. If it is taken, add another name.'
                              : null,
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          if (_isRegistering) {
                            if (value == null ||
                                !isRoleUsername(value.trim(), _requestedRole)) {
                              final suffix = _requestedRole == 'teacher'
                                  ? 'Teacher'
                                  : 'Student';
                              return 'Use a name ending in @$suffix.edu';
                            }
                            return null;
                          }
                          return Validators.username(value);
                        },
                      ),
                      if (_isRegistering) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (value) =>
                              _isRegistering ? Validators.email(value) : null,
                        ),
                        const SizedBox(height: 14),
                        const SizedBox(height: 18),
                        Text(
                          'School and class information',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _schoolSelector(),
                        const SizedBox(height: 14),
                        _sectionSelector(),
                        const SizedBox(height: 14),
                        if (_requestedRole == 'teacher') ...[
                          TextFormField(
                            controller: _subjectController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Main subject you teach',
                              prefixIcon: Icon(Icons.menu_book_outlined),
                            ),
                            validator: (value) =>
                                _isRegistering &&
                                    _requestedRole == 'teacher' &&
                                    (value == null || value.trim().isEmpty)
                                ? 'Enter your subject'
                                : null,
                          ),
                        ],
                      ],
                      if (_isRegistering) ...[
                        const SizedBox(height: 18),
                        Text(
                          'Set your password',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        autofillHints: _isRegistering
                            ? const [AutofillHints.newPassword]
                            : const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        obscureText: _obscurePassword,
                        validator: (value) {
                          if (!_isRegistering) {
                            return Validators.password(value);
                          }
                          if (value == null || value.length < 8) {
                            return 'Use at least 8 characters';
                          }
                          return null;
                        },
                      ),
                      if (_isRegistering) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirmController,
                          obscureText: _obscureConfirmation,
                          decoration: InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: const Icon(Icons.lock_reset_outlined),
                            suffixIcon: IconButton(
                              tooltip: _obscureConfirmation
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () => setState(
                                () => _obscureConfirmation =
                                    !_obscureConfirmation,
                              ),
                              icon: Icon(
                                _obscureConfirmation
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (_isRegistering &&
                                value != _passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                      ],
                      if (!_isRegistering)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _sendReset,
                            child: const Text('Forgot password?'),
                          ),
                        ),
                    ],
                  ),
                  if (authState.error != null) ...[
                    const SizedBox(height: 14),
                    _MessageBanner(message: authState.error!, isError: true),
                  ],
                  if (authState.successMessage != null) ...[
                    const SizedBox(height: 14),
                    _MessageBanner(message: authState.successMessage!),
                  ],
                  if (widget.registrationPage &&
                      authState.successMessage != null) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => _navigateToAuthRoute('/login'),
                      child: const Text('Go to sign in'),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed:
                        authState.isLoading ||
                            (widget.registrationPage &&
                                authState.successMessage != null) ||
                            (_isRegistering &&
                                (!_schoolsReady || _selectedSectionId == null))
                        ? null
                        : _submit,
                    icon: authState.isLoading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _isRegistering
                                ? Icons.person_add_alt_1
                                : Icons.login,
                          ),
                    label: Text(
                      authState.isLoading
                          ? 'Please wait…'
                          : _isRegistering
                          ? 'Create account'
                          : 'Sign in',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () => _navigateToAuthRoute(
                      widget.registrationPage ? '/login' : '/register',
                    ),
                    child: Text(
                      widget.registrationPage
                          ? 'Already have an account? Sign in'
                          : 'Create an account',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendReset() async {
    final input = _usernameController.text.trim();
    if (!input.contains('@')) {
      ref
          .read(authStateProvider.notifier)
          .setMessage(
            error: 'Enter your email address above to receive a reset link.',
          );
      return;
    }
    await ref.read(authStateProvider.notifier).sendPasswordReset(input);
  }

  Widget _schoolSelector() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _schoolsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Could not load schools: ${snapshot.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _schoolsReady = false;
                  _schoolsFuture = _loadSchools();
                }),
                child: const Text('Try again'),
              ),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const LinearProgressIndicator();
        }
        final schools = snapshot.data!;
        if (schools.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('No schools are available for registration yet.'),
              TextButton(
                onPressed: () => setState(() {
                  _schoolsReady = false;
                  _schoolsFuture = _loadSchools();
                }),
                child: const Text('Try again'),
              ),
            ],
          );
        }
        return DropdownButtonFormField<String>(
          key: ValueKey(_selectedSchoolId),
          initialValue: _selectedSchoolId,
          decoration: const InputDecoration(
            labelText: 'Your school',
            prefixIcon: Icon(Icons.school_outlined),
          ),
          items: [
            for (final school in schools)
              DropdownMenuItem<String>(
                value: school['id'] as String,
                child: Text(school['name'] as String? ?? 'School'),
              ),
          ],
          onChanged: (schoolId) {
            setState(() {
              _selectedSchoolId = schoolId;
              _selectedSectionId = null;
              _selectedSectionGradeName = null;
              _selectedTeacherClassName = null;
              _sectionsFuture = schoolId == null
                  ? Future.value([])
                  : _loadSections(schoolId);
            });
          },
          validator: (schoolId) =>
              schoolId == null ? 'Choose your school' : null,
        );
      },
    );
  }

  Widget _sectionSelector() {
    if (_selectedSchoolId == null) {
      return const Text('Choose a school to select your grade and section.');
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _sectionsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Could not load grade sections: ${snapshot.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: () => setState(
                  () => _sectionsFuture = _loadSections(_selectedSchoolId!),
                ),
                child: const Text('Try loading sections again'),
              ),
            ],
          );
        }
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final sections = snapshot.data!;
        if (sections.isEmpty) {
          return const Text(
            'No grade sections are available. Ask your school administrator to set them up.',
          );
        }
        return DropdownButtonFormField<String>(
          key: ValueKey(_selectedSchoolId),
          initialValue: _selectedSectionId,
          decoration: const InputDecoration(
            labelText: 'Grade and class or section',
            prefixIcon: Icon(Icons.class_outlined),
          ),
          items: [
            for (final section in sections)
              DropdownMenuItem<String>(
                value: section['id'] as String,
                child: Text(
                  '${(section['school_grades'] as Map<String, dynamic>)['name']} · ${section['name']}',
                ),
              ),
          ],
          onChanged: (sectionId) {
            final section = sections
                .where((item) => item['id'] == sectionId)
                .firstOrNull;
            final schoolGrade =
                section?['school_grades'] as Map<String, dynamic>?;
            setState(() {
              _selectedSectionId = sectionId;
              _selectedSectionGradeName = schoolGrade?['name'] as String?;
              _selectedTeacherClassName = section?['name'] as String?;
            });
          },
          validator: (sectionId) =>
              sectionId == null ? 'Choose your grade and section' : null,
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadSections(String schoolId) async {
    final rows = await ref
        .read(authStateProvider.notifier)
        .loadSections(schoolId);
    return rows;
  }

  Future<List<Map<String, dynamic>>> _loadSchools() async {
    try {
      final schools = await ref.read(authStateProvider.notifier).loadSchools();
      if (mounted) setState(() => _schoolsReady = schools.isNotEmpty);
      return schools;
    } catch (_) {
      if (mounted) setState(() => _schoolsReady = false);
      rethrow;
    }
  }

  void _updateGeneratedUsername() {
    _usernameController.text = roleUsername(
      _nameController.text,
      _requestedRole,
    );
  }
}

class _AnimatedWelcomePanel extends StatefulWidget {
  const _AnimatedWelcomePanel({this.compact = false});

  final bool compact;

  @override
  State<_AnimatedWelcomePanel> createState() => _AnimatedWelcomePanelState();
}

class _AnimatedWelcomePanelState extends State<_AnimatedWelcomePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  static const _colors = [
    Color(0xFF164B83),
    Color(0xFF087E8B),
    Color(0xFF12345A),
    Color(0xFF164B83),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Color _colorAt(double progress) {
    final scaled = progress * (_colors.length - 1);
    final index = scaled.floor().clamp(0, _colors.length - 2);
    return Color.lerp(_colors[index], _colors[index + 1], scaled - index)!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, _) {
        final progress = _animationController.value;
        return Container(
          height: widget.compact ? 184 : null,
          width: double.infinity,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _colorAt(progress),
                _colorAt((progress + 0.28) % 1),
                const Color(0xFF111B4D),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: _colorAt(progress).withValues(alpha: 0.22),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: widget.compact ? -48 : -34,
                top: widget.compact ? -80 : -110,
                child: _GlowOrb(
                  size: widget.compact ? 180 : 280,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              Positioned(
                left: widget.compact ? -45 : -75,
                bottom: widget.compact ? -110 : -160,
                child: _GlowOrb(
                  size: widget.compact ? 180 : 300,
                  color: const Color(0xFF60E5FF).withValues(alpha: 0.16),
                ),
              ),
              if (widget.compact)
                _buildCompactContent(theme, progress)
              else
                _buildWideContent(theme, progress),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactContent(ThemeData theme, double progress) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width * 0.48,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HIGH SCHOOL\nQUIZ APP',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.04,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Learn, teach, and grow together.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 2,
          child: _QuizIllustration(progress: progress, compact: true),
        ),
      ],
    );
  }

  Widget _buildWideContent(ThemeData theme, double progress) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final compactText = constraints.maxWidth < 700;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 24 : 36,
            30,
            compact ? 20 : 30,
            28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _BrandMark(inverse: true),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HIGH SCHOOL\nQUIZ APP',
                          style:
                              (compactText
                                      ? theme.textTheme.headlineMedium
                                      : theme.textTheme.displaySmall)
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    height: 1.05,
                                    letterSpacing: -0.6,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'A welcoming space for quizzes, confident teaching, and progress you can see.',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.82),
                            height: 1.5,
                          ),
                        ),
                        if (!compact) ...[
                          const SizedBox(height: 28),
                          const _BenefitTile(
                            icon: Icons.auto_awesome_outlined,
                            title: 'Made for focus',
                            detail: 'A clear, calm experience on any screen.',
                            inverse: true,
                          ),
                          const SizedBox(height: 14),
                          const _BenefitTile(
                            icon: Icons.insights_outlined,
                            title: 'Progress that matters',
                            detail:
                                'Keep your activities and results together.',
                            inverse: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: compact ? 8 : 18),
                  _QuizIllustration(progress: progress, compact: compact),
                ],
              ),
              const Spacer(),
            ],
          ),
        );
      },
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
    ),
  );
}

class _QuizIllustration extends StatelessWidget {
  const _QuizIllustration({required this.progress, this.compact = false});

  final double progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tilt = (progress - 0.5) * 0.07;
    final width = compact ? 155.0 : 250.0;
    final height = compact ? 132.0 : 220.0;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 8,
            bottom: 10,
            child: Transform.rotate(
              angle: -tilt,
              child: Container(
                width: compact ? 130 : 205,
                height: compact ? 100 : 156,
                decoration: BoxDecoration(
                  color: const Color(0xFF6AE1D3),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.auto_stories_rounded,
                  size: compact ? 48 : 72,
                  color: const Color(0xFF124B68),
                ),
              ),
            ),
          ),
          Positioned(
            left: 4,
            top: compact ? 12 : 22,
            child: Transform.rotate(
              angle: tilt,
              child: Container(
                width: compact ? 118 : 184,
                padding: EdgeInsets.all(compact ? 12 : 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: compact ? 24 : 32,
                          height: compact ? 24 : 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE9E8FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.quiz_rounded,
                            size: compact ? 15 : 20,
                            color: const Color(0xFF5847D8),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'QUICK QUIZ',
                          style: TextStyle(
                            color: const Color(0xFF5146B8),
                            fontSize: compact ? 8 : 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 10 : 16),
                    Container(
                      height: compact ? 7 : 9,
                      width: compact ? 84 : 132,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAEBF3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: compact ? 7 : 9,
                      width: compact ? 65 : 104,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAEBF3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    SizedBox(height: compact ? 10 : 16),
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF35B99A),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'You’ve got this!',
                          style: TextStyle(
                            color: const Color(0xFF27304A),
                            fontSize: compact ? 9 : 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: compact ? 0 : 0,
            top: compact ? 0 : 5,
            child: Container(
              width: compact ? 38 : 52,
              height: compact ? 38 : 52,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD166),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                Icons.star_rounded,
                color: const Color(0xFF674600),
                size: compact ? 23 : 31,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.only(top: 10), child: _BrandMark());
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.inverse = false});

  final bool inverse;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 46,
          width: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: inverse
                ? Colors.white.withValues(alpha: 0.18)
                : Theme.of(context).colorScheme.primary,
          ),
          child: Icon(
            Icons.auto_stories_rounded,
            color: inverse
                ? Colors.white
                : Theme.of(context).colorScheme.onPrimary,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'HIGH SCHOOL\nQUIZ APP',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: inverse ? Colors.white : null,
            fontWeight: FontWeight.w900,
            height: 1.05,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({
    required this.icon,
    required this.title,
    required this.detail,
    this.inverse = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          color: inverse
              ? const Color(0xFF8FF3E0)
              : Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(
              detail,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: inverse ? Colors.white.withValues(alpha: 0.75) : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = isError ? colors.errorContainer : colors.primaryContainer;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isError ? colors.onErrorContainer : colors.onPrimaryContainer,
        ),
      ),
    );
  }
}
