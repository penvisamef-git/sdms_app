import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/services.dart';

/// A session opened with a deep link must confirm the password before it signs or returns a document.
/// Returns true when the server accepted the password (good for 10 minutes), false when cancelled.
Future<bool> showConfirmPasswordDialog(BuildContext context, Api api) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ConfirmPasswordDialog(api: api),
  );
  return ok == true;
}

class _ConfirmPasswordDialog extends StatefulWidget {
  const _ConfirmPasswordDialog({required this.api});

  final Api api;

  @override
  State<_ConfirmPasswordDialog> createState() => _ConfirmPasswordDialogState();
}

class _ConfirmPasswordDialogState extends State<_ConfirmPasswordDialog> {
  final _ctl = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String _error = '';

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_ctl.text.isEmpty) {
      setState(() => _error = 'សូមបញ្ចូលពាក្យសម្ងាត់');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await widget.api.confirmPassword(_ctl.text);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('បញ្ជាក់ពាក្យសម្ងាត់'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('សូមបញ្ចូលពាក្យសម្ងាត់ មុនចុះហត្ថលេខា ឬត្រឡប់ឯកសារ (ចូលតាម Link)។ ការបញ្ជាក់មានសុពលភាព ១០ នាទី។'),
          const SizedBox(height: 12),
          TextField(
            controller: _ctl,
            enabled: !_busy,
            autofocus: true,
            obscureText: !_show,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'ពាក្យសម្ងាត់',
              suffixIcon: IconButton(
                icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('បោះបង់')),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'កំពុងពិនិត្យ...' : 'បញ្ជាក់')),
      ],
    );
  }
}
