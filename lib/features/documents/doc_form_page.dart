import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../data/cloudinary_upload.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/date_field.dart';
import '../../widgets/file_picker_field.dart';
import '../../widgets/org_tree_picker.dart';
import '../../widgets/receiver_card.dart';
import '../../widgets/select_sheet.dart';

/// One reference document row in the form.
class _Ref {
  _Ref({
    this.number = '',
    this.date = '',
    this.objective = '',
    List<Json>? existing,
  })  : existing = existing ?? [],
        numberCtl = TextEditingController(text: number),
        objectiveCtl = TextEditingController(text: objective),
        files = [];

  String number;
  String date;
  String objective;
  final TextEditingController numberCtl;
  final TextEditingController objectiveCtl;
  List<Json> existing; // already saved (edit)
  List<LocalFile> files; // new

  bool get used =>
      numberCtl.text.trim().isNotEmpty ||
      objectiveCtl.text.trim().isNotEmpty ||
      date.isNotEmpty ||
      files.isNotEmpty ||
      existing.isNotEmpty;

  void dispose() {
    numberCtl.dispose();
    objectiveCtl.dispose();
  }
}

String _dateInput(dynamic v) {
  final d = parseApiDate(v);
  return d == null ? '' : toApiDate(d);
}

/// Create (documentId == null) or edit a document (ឯកសារចេញ). Files go straight to Cloudinary.
class DocFormPage extends ConsumerStatefulWidget {
  const DocFormPage({super.key, this.documentId});

  final String? documentId;

  @override
  ConsumerState<DocFormPage> createState() => _DocFormPageState();
}

class _DocFormPageState extends ConsumerState<DocFormPage> {
  final _objective = TextEditingController();
  final _number = TextEditingController();
  final _note = TextEditingController();
  final _sendNote = TextEditingController();
  String _dateSign = '';
  String _dateIn = '';
  String _dateReg = '';
  String _typeId = '';
  String _frameworkId = '';
  String _flowId = '';

  List<LocalFile> _mainFiles = [];
  List<Json> _mainKept = [];
  final List<_Ref> _refs = [];

  OrgPick? _toOffice;
  String _toUserId = '';

  List<Json> _types = [];
  List<Json> _frameworks = [];
  List<Json> _flows = [];
  List<Json> _tree = [];
  List<Json> _users = [];

  Json? _doc;
  Json? _tracking;
  bool _loading = true;
  bool _saving = false;
  double? _uploadPct;
  String _error = '';

  bool get _isEdit => widget.documentId != null;
  Json? get _me => ref.read(authProvider).user;
  String get _myOfficeId => idOf(_me?['office_id']);

  bool get _notOwner =>
      _isEdit && _doc != null && _me?['is_super_admin'] != true && idOf(_doc!['office_id_open']) != _myOfficeId;
  bool get _alreadyReceived =>
      _isEdit &&
      _doc != null &&
      (_tracking != null
          ? asList(_tracking!['timeline']).any((t) => s(t['status']) != 'pending')
          : s(_doc!['status']) != 'new');
  bool get _locked => _notOwner || _alreadyReceived;
  bool get _busy => _saving || _loading || _locked;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _objective.dispose();
    _number.dispose();
    _note.dispose();
    _sendNote.dispose();
    for (final r in _refs) {
      r.dispose();
    }
    super.dispose();
  }

  Future<List<Json>> _safe(Future<Json> f) async {
    try {
      return asList((await f)['data']);
    } catch (_) {
      return <Json>[];
    }
  }

  Future<void> _init() async {
    final api = ref.read(apiProvider);
    final r = await Future.wait([
      _safe(api.statusOfProcess.all()),
      _safe(api.documentTypes.all()),
      _safe(api.frameworks.all()),
      _safe(api.unitTree()),
      _safe(api.allUsers()),
    ]);
    _flows = r[0];
    _types = r[1];
    _frameworks = r[2];
    _tree = r[3];
    _users = r[4];

    if (_isEdit) {
      try {
        final res = await api.document(widget.documentId!);
        final d = asObj(res['data']);
        Json? track;
        try {
          track = asObj((await api.documentTracking(widget.documentId!))['data']);
        } catch (_) {}
        _doc = d;
        _tracking = track;
        _objective.text = s(d['objective']);
        _number.text = s(d['number_document']);
        _note.text = s(d['note_from_user']);
        _dateSign = _dateInput(d['date_sign']);
        _dateIn = _dateInput(d['date_in']);
        _dateReg = _dateInput(d['date_registration_document']);
        _typeId = idOf(d['document_type_id']);
        _frameworkId = idOf(d['framework_id']);
        _flowId = idOf(d['status_of_process_id']);
        _mainKept = asList(d['document_main_url']);
        for (final rf in asList(d['reference_document'])) {
          _refs.add(_Ref(
            number: s(rf['number_document']),
            date: _dateInput(rf['date_sign']),
            objective: s(rf['objective']),
            existing: asList(rf['files']),
          ));
        }
      } catch (e) {
        _error = e.toString();
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Option> _opts(List<Json> list) => [
        for (final i in list)
          Option(s(i['_id']), s(i['code']).isNotEmpty ? '${s(i['code'])} - ${s(i['name'])}' : s(i['name'])),
      ];

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_locked || _loading) return;
    setState(() => _error = '');

    if (_objective.text.trim().isEmpty) {
      setState(() => _error = 'សូមបញ្ចូល កម្មវត្ថុ');
      return;
    }

    final used = _refs.where((r) => r.used).toList();
    final total = _mainFiles.length + _mainKept.length + used.fold<int>(0, (a, r) => a + r.files.length + r.existing.length);
    if (total > maxFiles) {
      setState(() => _error = 'អាចបញ្ចូលបានអតិបរមា $maxFiles ឯកសារ (បច្ចុប្បន្ន $total)');
      return;
    }

    final api = ref.read(apiProvider);
    setState(() {
      _saving = true;
      _uploadPct = null;
    });
    try {
      // 1) upload every new file straight to Cloudinary
      final groups = <({List<LocalFile> files, String folder})>[
        (files: _mainFiles, folder: 'documents'),
        for (final r in used) (files: r.files, folder: 'references'),
      ];
      final totalBytes = groups.fold<int>(0, (a, g) => a + g.files.fold<int>(0, (b, f) => b + f.size));
      var before = 0;
      final uploaded = <List<Json>>[];
      for (final g in groups) {
        final size = g.files.fold<int>(0, (b, f) => b + f.size);
        if (g.files.isEmpty) {
          uploaded.add([]);
          continue;
        }
        final base = before;
        uploaded.add(await uploadToCloudinary(
          api,
          g.files,
          g.folder,
          onProgress: (fr) {
            if (mounted && totalBytes > 0) setState(() => _uploadPct = (base + fr * size) / totalBytes);
          },
        ));
        before += size;
      }
      if (mounted) setState(() => _uploadPct = null);

      final mainUp = uploaded.first;
      final refUp = uploaded.skip(1).toList();

      final refsBody = [
        for (var i = 0; i < used.length; i++)
          {
            'number_document': used[i].numberCtl.text.trim(),
            'date_sign': used[i].date.isEmpty ? null : used[i].date,
            'objective': used[i].objectiveCtl.text.trim(),
            'files': [...used[i].existing, ...refUp[i]],
          },
      ];

      final fields = <String, dynamic>{
        'objective': _objective.text.trim(),
        'number_document': _number.text.trim(),
        'note_from_user': _note.text.trim(),
        'date_sign': _dateSign.isEmpty ? null : _dateSign,
        'date_in': _dateIn.isEmpty ? null : _dateIn,
        'date_registration_document': _dateReg.isEmpty ? null : _dateReg,
        'document_type_id': _typeId.isEmpty ? null : _typeId,
        'framework_id': _frameworkId.isEmpty ? null : _frameworkId,
        'status_of_process_id': _flowId.isEmpty ? null : _flowId,
      };

      final offices = _toOffice?.offices ?? <String>[];
      final hasReceiver = offices.isNotEmpty || _toUserId.isNotEmpty;

      Json res;
      if (_isEdit) {
        res = await api.documentUpdate(widget.documentId!, {
          ...fields,
          'document_main_url': [..._mainKept, ...mainUp],
          'reference_document': refsBody,
        });
        if (hasReceiver) {
          res = await api.documentSend(widget.documentId!, {
            'send_to_office_id': offices,
            'send_to_user_id': _toUserId.isEmpty ? <String>[] : [_toUserId],
            'note': _sendNote.text,
          });
        }
      } else {
        final body = <String, dynamic>{
          for (final e in fields.entries)
            if (e.value != null && s(e.value).trim().isNotEmpty) e.key: e.value,
          if (offices.isNotEmpty) 'send_to_office_id': offices,
          if (_toUserId.isNotEmpty) 'send_to_user_id': [_toUserId],
          if (_sendNote.text.trim().isNotEmpty) 'send_note': _sendNote.text.trim(),
          if (mainUp.isNotEmpty) 'document_main_url': mainUp,
          if (refsBody.isNotEmpty) 'reference_document': refsBody,
        };
        res = await api.documentCreate(body);
      }

      if (!mounted) return;
      showSnack(context, s(res['message']).isNotEmpty ? s(res['message']) : 'បានរក្សាទុក!');
      context.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
          _uploadPct = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sentNames = _doc == null
        ? <String>[]
        : [
            ...asList(_doc!['send_to_office_id']).map((o) => s(o['name'])),
            ...asList(_doc!['send_to_user_id']).map(personName),
          ].where((e) => e.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'កែប្រែឯកសារចេញ' : 'ឯកសារចេញថ្មី')),
      bottomNavigationBar: _locked
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving
                      ? (_uploadPct != null ? 'កំពុង upload ${(_uploadPct! * 100).round()}%' : 'កំពុងរក្សាទុក...')
                      : 'រក្សាទុក'),
                ),
              ),
            ),
      body: _loading
          ? const LoadingList(count: 4)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (_isEdit && _doc != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      color: _locked ? AppColors.warn.withValues(alpha: 0.1) : AppColors.soft,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(_locked ? Icons.lock_outline : Icons.edit_note, color: _locked ? AppColors.warn : AppColors.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _locked
                                    ? (_notOwner
                                        ? 'អ្នកមិនមានសិទ្ធិកែប្រែឯកសារនេះទេ'
                                        : 'មិនអាចកែប្រែបានទេ ព្រោះមានអ្នកទទួលឯកសារនេះរួចហើយ')
                                    : s(_doc!['code_of_document']),
                                style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ----- receivers -----
                if (_isEdit && sentNames.isNotEmpty)
                  SectionCard(
                    title: 'អ្នកទទួល',
                    child: Text('ឯកសារនេះត្រូវបានផ្ញើរួចហើយទៅ: ${sentNames.join(', ')}'),
                  )
                else
                  ReceiverCard(
                    tree: _tree,
                    users: _users,
                    myOfficeId: _myOfficeId,
                    myUserId: s(_me?['_id']),
                    office: _toOffice,
                    userId: _toUserId,
                    disabled: _busy,
                    onOfficeChanged: (v) => setState(() => _toOffice = v),
                    onUserChanged: (v) => setState(() => _toUserId = v),
                    footer: TextField(
                      controller: _sendNote,
                      enabled: !_busy,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'ការណែនាំដល់អ្នកទទួល',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),

                // ----- information -----
                SectionCard(
                  title: 'ព័ត៌មានឯកសារ',
                  child: Column(
                    children: [
                      TextField(
                        controller: _objective,
                        enabled: !_busy,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(labelText: 'កម្មវត្ថុ *', alignLabelWithHint: true),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _number,
                        enabled: !_busy,
                        decoration: const InputDecoration(labelText: 'លេខឯកសារ', hintText: 'ឧ. ១២៣/២៦ សហវ'),
                      ),
                      const SizedBox(height: 14),
                      DateField(
                        label: 'កាលបរិច្ឆេទចុះហត្ថលេខា',
                        value: _dateSign,
                        enabled: !_busy,
                        onChanged: (v) => setState(() => _dateSign = v),
                      ),
                      const SizedBox(height: 14),
                      DateField(
                        label: 'កាលបរិច្ឆេទចូល',
                        value: _dateIn,
                        enabled: !_busy,
                        onChanged: (v) => setState(() => _dateIn = v),
                      ),
                      const SizedBox(height: 14),
                      DateField(
                        label: 'ចុះលេខចេញ',
                        value: _dateReg,
                        enabled: !_busy,
                        onChanged: (v) => setState(() => _dateReg = v),
                      ),
                      const SizedBox(height: 14),
                      SelectField(
                        label: 'ប្រភេទឯកសារ',
                        options: _opts(_types),
                        value: _typeId,
                        enabled: !_busy,
                        onChanged: (v) => setState(() => _typeId = v),
                      ),
                      const SizedBox(height: 14),
                      SelectField(
                        label: 'ក្របខណ្ឌឯកសារ',
                        options: _opts(_frameworks),
                        value: _frameworkId,
                        enabled: !_busy,
                        onChanged: (v) => setState(() => _frameworkId = v),
                      ),
                      const SizedBox(height: 14),
                      SelectField(
                        label: 'លំហូរឯកសារ',
                        options: _opts(_flows),
                        value: _flowId,
                        enabled: !_busy,
                        onChanged: (v) => setState(() => _flowId = v),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _note,
                        enabled: !_busy,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(labelText: 'កំណត់សម្គាល់', alignLabelWithHint: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ----- main files -----
                SectionCard(
                  title: 'ឯកសារគោល',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isEdit) _savedFiles(_mainKept, (l) => setState(() => _mainKept = l)),
                      FilePickerField(
                        files: _mainFiles,
                        disabled: _busy,
                        onChanged: (l) => setState(() => _mainFiles = l),
                        hint: 'អតិបរមា $maxFileMb MB ក្នុងមួយឯកសារ · សរុបមិនលើស $maxFiles ឯកសារ',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ----- references -----
                SectionCard(
                  title: 'ឯកសារយោង',
                  trailing: TextButton.icon(
                    onPressed: _busy ? null : () => setState(() => _refs.add(_Ref())),
                    icon: const Icon(Icons.add),
                    label: const Text('បន្ថែម'),
                  ),
                  child: _refs.isEmpty
                      ? Text('មិនទាន់មានឯកសារយោង', style: t.bodyMedium?.copyWith(color: AppColors.muted))
                      : Column(
                          children: [
                            for (var i = 0; i < _refs.length; i++) _refCard(i),
                          ],
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
                    child: Text(_error, style: const TextStyle(color: AppColors.danger)),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _savedFiles(List<Json> files, ValueChanged<List<Json>> onChange) {
    if (files.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (var i = 0; i < files.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              color: AppColors.soft.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_done_outlined, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s(files[i]['original_name']).isEmpty ? s(files[i]['public_id']) : s(files[i]['original_name']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(formatBytes(files[i]['bytes']), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _busy ? null : () => onChange([...files]..removeAt(i)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _refCard(int i) {
    final r = _refs[i];
    return Container(
      margin: EdgeInsets.only(bottom: i == _refs.length - 1 ? 0 : 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('ឯកសារយោងទី ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800))),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _refs.removeAt(i).dispose();
                        }),
              ),
            ],
          ),
          TextField(
            controller: r.numberCtl,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'លេខឯកសារ'),
          ),
          const SizedBox(height: 12),
          DateField(
            label: 'កាលបរិច្ឆេទចុះហត្ថលេខា',
            value: r.date,
            enabled: !_busy,
            onChanged: (v) => setState(() => r.date = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: r.objectiveCtl,
            enabled: !_busy,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'កម្មវត្ថុ', alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          if (_isEdit) _savedFiles(r.existing, (l) => setState(() => r.existing = l)),
          FilePickerField(
            files: r.files,
            disabled: _busy,
            onChanged: (l) => setState(() => r.files = l),
          ),
        ],
      ),
    );
  }
}
