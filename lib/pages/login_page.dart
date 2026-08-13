import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../services/case_api.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../widgets/brand_mark.dart';
import '../models/login_response.dart';
import 'dashboard_page.dart';

class LoginPage extends StatefulWidget {
  /// Stand-in for the backend, supplied by tests. When null the page builds
  /// its own client and closes it on dispose.
  final Api? api;

  const LoginPage({super.key, this.api});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController(text: '');
  final _passCtrl = TextEditingController(text: '');
  bool _obscure = true;
  bool _loading = false;

  /// Why the last attempt failed, shown above the button. Cleared on the next
  /// try so a stale message never sits under a fresh attempt.
  String? _error;

  /// Only set when the page built the client itself — an injected [Api]
  /// belongs to the caller and must not be closed here.
  ApiClient? _ownedClient;
  late final Api _api;

  @override
  void initState() {
    super.initState();
    final injected = widget.api;
    if (injected != null) {
      _api = injected;
    } else {
      _ownedClient = ApiClient();
      _api = Api(_ownedClient!);
    }
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _ownedClient?.close();
    super.dispose();
  }

  Future<void> _submit() async {
    // The sign-in button disables itself while this runs, but the password
    // field's submit action does not go through it — pressing Enter twice
    // would otherwise push two dashboards, each fetching the case list on its
    // own initState.
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final LoginResponse session;
    try {
      session = await _api.login(
        name: _userCtrl.text.trim(),
        password: _passCtrl.text,
      );
    } on ApiException catch (e) {
      // Shown on the form rather than thrown: the user is one correction away
      // from getting in, and a dead screen would not tell them which field.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => DashboardPage(session: session),
        transitionsBuilder:
            (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final form = _LoginForm(
            formKey: _formKey,
            error: _error,
            userCtrl: _userCtrl,
            passCtrl: _passCtrl,
            obscure: _obscure,
            loading: _loading,
            onToggleObscure: () => setState(() => _obscure = !_obscure),
            onSubmit: _submit,
          );
          if (!wide) {
            return Container(
              color: AppColors.canvas,
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(context.gutter),
                  child: form,
                ),
              ),
            );
          }
          return Row(
            children: [
              const Expanded(flex: 5, child: _BrandPanel()),
              Expanded(
                flex: 4,
                child: Container(
                  color: AppColors.canvas,
                  alignment: Alignment.center,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(context.gutter * 1.4),
                    child: form,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Left branded hero panel shown on wide screens.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primary, Color(0xFF244B85)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -60,
            top: -40,
            child: _Blob(size: 260, opacity: 0.10),
          ),
          const Positioned(
            left: -80,
            bottom: -60,
            child: _Blob(size: 320, opacity: 0.08),
          ),
          Padding(
            padding: EdgeInsets.all(context.widthClamp(0.05, 32, 56)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BrandMark(size: 44, onDark: true),
                    const SizedBox(width: 14),
                    Text(
                      'SMART',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall!.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  'Self Monitoring &\nReconciliation Tracker',
                  style: Theme.of(context).textTheme.displaySmall!.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'A single control room for tracking, verifying and resolving '
                  'reconciliation breaks across processing units.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 16,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 40),
                Row(
                  children: const [
                    _HeroStat(value: '20,032', label: 'Cases tracked'),
                    SizedBox(width: 40),
                    _HeroStat(value: '99.2%', label: 'Match rate'),
                    SizedBox(width: 40),
                    _HeroStat(value: '6', label: 'Processing units'),
                  ],
                ),
                const Spacer(),
                Text(
                  '© 2026 SMART · Internal use only',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;
  const _HeroStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final double opacity;
  const _Blob({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController userCtrl;
  final TextEditingController passCtrl;
  final bool obscure;
  final bool loading;

  /// Why the last attempt failed, or null when there is nothing to report.
  final String? error;

  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;

  const _LoginForm({
    required this.formKey,
    this.error,
    required this.userCtrl,
    required this.passCtrl,
    required this.obscure,
    required this.loading,
    required this.onToggleObscure,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, c) {
                // Show a compact brand mark on narrow screens where the hero
                // panel is hidden.
                final showMark = MediaQuery.of(context).size.width < 900;
                if (!showMark) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: Row(
                    children: [
                      const BrandMark(size: 40),
                      const SizedBox(width: 12),
                      Text(
                        'SMART',
                        style: Theme.of(
                          context,
                        ).textTheme.headlineSmall!.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Text(
              'Welcome back',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to your monitoring workspace.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 32),
            const _FieldLabel('Username'),
            const SizedBox(height: 8),
            TextFormField(
              controller: userCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'e.g. ninad.thakur',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
              validator:
                  (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'Enter your username'
                          : null,
            ),
            const SizedBox(height: 20),
            const _FieldLabel('Password'),
            const SizedBox(height: 8),
            TextFormField(
              controller: passCtrl,
              obscureText: obscure,
              onFieldSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                hintText: '••••••••',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: onToggleObscure,
                ),
              ),
              validator:
                  (v) =>
                      (v == null || v.isEmpty) ? 'Enter your password' : null,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {},
                child: const Text('Forgot password?'),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 4),
              _ErrorBanner(error!),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: loading ? null : onSubmit,
                child:
                    loading
                        ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                        : const Text(
                          'Sign in',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 15,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  'Secured internal access',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }
}

/// What the sign-in service said went wrong, shown above the button.
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
