import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Change my own password (its own page, opened from the account tab).
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;
  bool _saving = false;
  String _error = '';

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = '');
    if (_old.text.isEmpty) return setState(() => _error = 'សូមបញ្ចូលពាក្យសម្ងាត់ចាស់');
    if (_new.text.isEmpty) return setState(() => _error = 'សូមបញ្ចូលពាក្យសម្ងាត់ថ្មី');
    if (_new.text.length < 8) return setState(() => _error = 'ពាក្យសម្ងាត់ថ្មីត្រូវមានយ៉ាងតិច ៨ តួអក្សរ');
    if (_new.text != _confirm.text) return setState(() => _error = 'ពាក្យសម្ងាត់បញ្ជាក់មិនត្រូវគ្នា');

    setState(() => _saving = true);
    try {
      final res = await ref.read(apiProvider).changePassword(_old.text, _new.text);
      if (!mounted) return;
      showSnack(context, s(res['message']).isNotEmpty ? s(res['message']) : 'បានប្តូរពាក្យសម្ងាត់ថ្មី!');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController c, String label) => TextField(
        controller: c,
        enabled: !_saving,
        obscureText: !_show,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            tooltip: _show ? 'លាក់' : 'បង្ហាញ',
            icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _show = !_show),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('ប្តូរពាក្យសម្ងាត់')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: const Icon(Icons.key_rounded),
            label: Text(_saving ? 'កំពុងរក្សាទុក...' : 'ប្តូរពាក្យសម្ងាត់'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Text('ឧបករណ៍ផ្សេងទៀតនឹងត្រូវចូលគណនីម្តងទៀត។ ពាក្យសម្ងាត់ថ្មីត្រូវមានយ៉ាងតិច ៨ តួអក្សរ។',
              style: t.bodyMedium?.copyWith(color: AppColors.muted)),
          const SizedBox(height: 20),
          _field(_old, 'ពាក្យសម្ងាត់ចាស់'),
          const SizedBox(height: 16),
          _field(_new, 'ពាក្យសម្ងាត់ថ្មី'),
          const SizedBox(height: 16),
          _field(_confirm, 'បញ្ជាក់ពាក្យសម្ងាត់ថ្មី'),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error, style: const TextStyle(color: AppColors.danger)),
            ),
        ],
      ),
    );
  }
}
