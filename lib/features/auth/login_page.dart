import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _show = false;
  bool _loading = false;
  String _error = '';
  bool _badEmail = false;
  bool _badPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = '';
      _badEmail = false;
      _badPassword = false;
    });

    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _error = 'សូមបំពេញព័ត៌មានទាំងអស់';
        _badEmail = email.isEmpty;
        _badPassword = password.isEmpty;
      });
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() {
        _error = 'អ៊ីមែលមិនត្រឹមត្រូវ';
        _badEmail = true;
      });
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(authProvider.notifier).login(email, password);
      // the router moves to /home by itself
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _error = msg;
        _badEmail = RegExp('អ៊ីមែល|email', caseSensitive: false).hasMatch(msg);
        _badPassword = RegExp('ពាក្យសម្ងាត់|password', caseSensitive: false).hasMatch(msg);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryDark, AppColors.primary, Color(0xFF0FA39B)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(Icons.description_rounded, color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'ប្រព័ន្ធគ្រប់គ្រងឯកសារ',
                      textAlign: TextAlign.center,
                      style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SDMS',
                      style: t.titleMedium?.copyWith(color: Colors.white70, letterSpacing: 4),
                    ),
                    const SizedBox(height: 28),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('ចូលគណនី', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _email,
                              enabled: !_loading,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => _passwordFocus.requestFocus(),
                              decoration: InputDecoration(
                                labelText: 'អ៊ីមែល',
                                prefixIcon: const Icon(Icons.mail_outline_rounded),
                                errorText: _badEmail ? '' : null,
                                errorStyle: const TextStyle(height: 0, fontSize: 0),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _password,
                              focusNode: _passwordFocus,
                              enabled: !_loading,
                              obscureText: !_show,
                              autofillHints: const [AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'ពាក្យសម្ងាត់',
                                prefixIcon: const Icon(Icons.lock_outline_rounded),
                                errorText: _badPassword ? '' : null,
                                errorStyle: const TextStyle(height: 0, fontSize: 0),
                                suffixIcon: IconButton(
                                  icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                  onPressed: () => setState(() => _show = !_show),
                                ),
                              ),
                            ),
                            if (_error.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.danger.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(_error, style: const TextStyle(color: AppColors.danger))),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _loading ? null : _submit,
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                    )
                                  : const Text('ចូលគណនី'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      AppInfo.versionText,
                      style: t.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
