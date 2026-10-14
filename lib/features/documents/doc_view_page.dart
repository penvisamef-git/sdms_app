import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/cloudinary_upload.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/org_tree_picker.dart';
import '../../widgets/receiver_card.dart';
import '../../widgets/select_sheet.dart';
import 'doc_helpers.dart';
import 'file_viewer_page.dart';
import 'tracking_panel.dart';

/// Detail page: information, files, actions (receive / forward / return / finish / send) and tracking.
class DocViewPage extends ConsumerStatefulWidget {
  const DocViewPage({super.key, required this.id, required this.box});

  final String id;
  final String box;

  @override
  ConsumerState<DocViewPage> createState() => _DocViewPageState();
}

class _DocViewPageState extends ConsumerState<DocViewPage> {
  Json? _doc;
  Json? _tracking;
  bool _loading = true;
  String _error = '';

  List<Json> _tree = [];
  List<Json> _users = [];
  List<Json> _flows = [];

  OrgPick? _toOffice;
  String _toUserId = '';
  String _flowId = '';
  final _note = TextEditingController();
  bool _busy = false;
  String _actionError = '';

  Json? get _me => ref.read(authProvider).user;
  String get _myOfficeId => idOf(_me?['office_id']);
  String get _myUserId => s(_me?['_id']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<List<Json>> _safe(Future<Json> f) async {
    try {
      return asList((await f)['data']);
    } catch (_) {
      return <Json>[];
    }
  }

  bool _optionsLoading = false;
  bool _optionsLoaded = false;

  /// Org tree / user list / flows are big and only needed to pick receivers: load them only when this
  /// user can forward or send (not for every document that is just opened to read).
  void _ensureOptions() {
    if (_optionsLoaded || _optionsLoading) return;
    if (!(_canAct || (_isOwner && !_alreadySent))) return;
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    _optionsLoading = true;
    final api = ref.read(apiProvider);
    final r = await Future.wait([
      _safe(api.unitTree()),
      _safe(api.allUsers()),
      _safe(api.statusOfProcess.all()),
    ]);
    _optionsLoading = false;
    if (!mounted) return;
    setState(() {
      _tree = r[0];
      _users = r[1];
      _flows = r[2];
      _optionsLoaded = r[0].isNotEmpty || r[1].isNotEmpty;
    });
  }

  Future<void> _load() async {
    final api = ref.read(apiProvider);
    setState(() {
      _loading = _doc == null;
      _error = '';
    });
    try {
      // both requests at the same time (they used to run one after the other)
      final results = await Future.wait<Json?>([
        api.document(widget.id),
        api.documentTracking(widget.id).then<Json?>((r) => r).catchError((_) => null),
      ]);
      final res = results[0] ?? <String, dynamic>{};
      final trackRes = results[1];
      if (!mounted) return;
      setState(() {
        _doc = asObj(res['data']);
        _tracking = trackRes == null ? null : asObj(trackRes['data']);
      });
      _ensureOptions();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ----- derived state (same rules as the web page) -----
  List<Json> get _timeline => asList(_tracking?['timeline']);

  Json? get _mine {
    final rows = _timeline.where((t) => isTransferReceiver(t, _me)).toList();
    Json? pick(String status) {
      final l = rows.where((t) => s(t['status']) == status).toList();
      return l.isEmpty ? null : l.last;
    }

    return pick('pending') ?? pick('received') ?? pick('forwarded') ?? (rows.isEmpty ? null : rows.last);
  }

  bool get _isOwner =>
      _doc != null && (_me?['is_super_admin'] == true || idOf(_doc!['office_id_open']) == _myOfficeId);

  bool get _canAct => s(_mine?['status']) == 'received';
  bool get _isPending => s(_mine?['status']) == 'pending';

  bool get _alreadySent =>
      _doc != null &&
      asList(_doc!['send_to_office_id']).length + asList(_doc!['send_to_user_id']).length > 0;

  bool get _editable => _isOwner && _timeline.every((t) => s(t['status']) == 'pending');

  bool get _hasReceiver => (_toOffice?.offices.isNotEmpty ?? false) || _toUserId.isNotEmpty;

  Json get _receivers => {
        'send_to_office_id': _toOffice?.offices ?? <String>[],
        'send_to_user_id': _toUserId.isEmpty ? <String>[] : [_toUserId],
      };

  Future<void> _run(Future<Json> Function() fn, String fallback) async {
    setState(() {
      _actionError = '';
      _busy = true;
    });
    try {
      final res = await fn();
      if (!mounted) return;
      showSnack(context, s(res['message']).isNotEmpty ? s(res['message']) : fallback);
      setState(() {
        _toOffice = null;
        _toUserId = '';
        _flowId = '';
        _note.clear();
      });
      await _load();
    } catch (e) {
      if (mounted) setState(() => _actionError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _needReceiver() {
    if (_hasReceiver) return true;
    setState(() => _actionError = 'សូមជ្រើសរើសអង្គភាព ឬអ្នកប្រើប្រាស់ទទួលយ៉ាងហោចណាស់មួយ');
    return false;
  }

  void _receive() => _run(() => ref.read(apiProvider).receive(s(_mine!['_id'])), 'បានទទួលឯកសារ!');

  void _forward() {
    if (!_needReceiver()) return;
    _run(
      () => ref.read(apiProvider).forward(s(_mine!['_id']), {
        ..._receivers,
        'note': _note.text,
        if (_flowId.isNotEmpty) 'status_of_process_id': _flowId,
      }),
      'បានបញ្ជូនបន្ត!',
    );
  }

  Future<void> _return() async {
    final ok = await confirmDialog(context, title: 'រុញឯកសារត្រឡប់?', message: 'ឯកសារនឹងត្រូវផ្ញើត្រឡប់ទៅអ្នកផ្ញើវិញ។');
    if (!ok) return;
    _run(
      () => ref.read(apiProvider).returnBack(s(_mine!['_id']), {
        'note': _note.text,
        if (_flowId.isNotEmpty) 'status_of_process_id': _flowId,
      }),
      'បានរុញត្រឡប់!',
    );
  }

  Future<void> _finish() async {
    final ok = await confirmDialog(context, title: 'បញ្ចប់នៅអង្គភាពខ្ញុំ?', message: 'អ្នកនឹងមិនអាចបញ្ជូនបន្តបានទៀតទេ។');
    if (!ok) return;
    _run(() => ref.read(apiProvider).done(s(_mine!['_id']), {'note': _note.text}), 'បានបញ្ចប់!');
  }

  void _send() {
    if (!_needReceiver()) return;
    _run(() => ref.read(apiProvider).documentSend(widget.id, {..._receivers, 'note': _note.text}), 'បានផ្ញើ!');
  }


  // ----- signed PDF: store it back (same rules as the web) -----
  static const int _maxSignedMb = 20;

  /// Why a signed copy cannot be saved right now ('' = it can).
  String get _saveBlockedReason {
    final mine = _mine;
    final holdsIt = s(mine?['status']) == 'pending' || s(mine?['status']) == 'received';
    if (holdsIt) return '';
    final wasSent = _alreadySent || _timeline.isNotEmpty;
    if (_isOwner) {
      if (!wasSent) return '';
      return mine != null
          ? 'ឯកសារត្រូវបាន${s(mine['status']) == 'forwarded' ? 'បញ្ជូនបន្ត' : 'ដំណើរការ'}រួចហើយ'
          : 'ឯកសារត្រូវបានផ្ញើរួចហើយ';
    }
    return mine != null ? 'ឯកសារត្រូវបានបញ្ជូនបន្តរួចហើយ' : 'អ្នកមិនមានសិទ្ធិលើឯកសារនេះទេ';
  }

  Future<Json> _saveSigned(Uint8List bytes, Json file) async {
    final doc = _doc;
    if (doc == null) throw ApiException('មិនមានឯកសារ');
    if (bytes.length > _maxSignedMb * 1024 * 1024) {
      throw ApiException('ឯកសារធំពេក! (អតិបរមា $_maxSignedMb MB)');
    }
    final api = ref.read(apiProvider);
    final oldId = s(file['public_id']);
    final mainList = asList(doc['document_main_url']);
    final mainIndex = mainList.indexWhere((f) => s(f['public_id']) == oldId);
    final refList = asList(doc['reference_document']);
    final refIndex = refList.indexWhere((r) => asList(r['files']).any((f) => s(f['public_id']) == oldId));
    if (mainIndex < 0 && refIndex < 0) throw ApiException('រកមិនឃើញឯកសារនេះក្នុងឯកសារដើមទេ');

    final name = s(file['original_name']).isEmpty ? 'document.pdf' : s(file['original_name']);

    // straight to Cloudinary (no size limit from the API)
    final dir = await getTemporaryDirectory();
    final tmp = File('${dir.path}/signed_${DateTime.now().microsecondsSinceEpoch}.pdf');
    await tmp.writeAsBytes(bytes, flush: true);
    Json saved;
    try {
      final up = await uploadToCloudinary(
        api,
        [LocalFile(path: tmp.path, name: name, size: bytes.length)],
        mainIndex >= 0 ? 'documents' : 'references',
      );
      saved = up.first;
    } finally {
      try {
        await tmp.delete();
      } catch (_) {}
    }
    saved['original_name'] = s(saved['original_name']).isEmpty ? name : saved['original_name'];

    // a receiver cannot edit the document: the API replaces the file for them
    if (!_isOwner) {
      final refFileIndex = refIndex >= 0
          ? asList(refList[refIndex]['files']).indexWhere((f) => s(f['public_id']) == oldId)
          : -1;
      final res = await api.documentReplaceFile(widget.id, {'public_id': oldId, 'file': saved});
      final d = asObj(res['data']);
      var fresh = asObj(res['file']);
      if (s(fresh['url']).isEmpty) {
        fresh = mainIndex >= 0
            ? (mainIndex < asList(d['document_main_url']).length ? asList(d['document_main_url'])[mainIndex] : <String, dynamic>{})
            : (refIndex < asList(d['reference_document']).length &&
                    refFileIndex >= 0 &&
                    refFileIndex < asList(asList(d['reference_document'])[refIndex]['files']).length
                ? asList(asList(d['reference_document'])[refIndex]['files'])[refFileIndex]
                : <String, dynamic>{});
      }
      if (s(fresh['url']).isEmpty) throw ApiException('រក្សាទុកមិនបានសម្រេច');
      return fresh;
    }

    // the creator office / a super admin edits the document itself
    final body = mainIndex >= 0
        ? <String, dynamic>{
            'document_main_url': [for (var i = 0; i < mainList.length; i++) i == mainIndex ? saved : mainList[i]],
          }
        : <String, dynamic>{
            'reference_document': [
              for (final r in refList)
                {
                  'number_document': s(r['number_document']),
                  'date_sign': s(r['date_sign']).isEmpty ? null : r['date_sign'],
                  'objective': s(r['objective']),
                  'files': [for (final f in asList(r['files'])) s(f['public_id']) == oldId ? saved : f],
                },
            ],
          };
    await api.documentUpdate(widget.id, body);
    return saved;
  }

  Future<void> _openFile(Json f) async {
    await context.push(
      '/file',
      extra: FileViewArgs(f, onSave: _saveSigned, saveBlockedReason: _saveBlockedReason),
    );
    if (mounted) {
      ref.read(apiClientProvider).clearCache();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final mineStatus = transferStatus[s(_mine?['status'])];
    final dStatus = doc == null ? null : docStatus[s(doc['status'])];
    final badge = mineStatus ?? dStatus;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: Text(doc == null ? 'ឯកសារ' : (s(doc['code_of_document']).isEmpty ? '-' : s(doc['code_of_document'])),
                  overflow: TextOverflow.ellipsis),
            ),
            if (badge != null) ...[const SizedBox(width: 10), StatusBadge(badge.label, tone: badge.tone)],
          ],
        ),
        actions: [
          if (doc != null && _isOwner)
            IconButton(
              tooltip: _editable ? 'កែប្រែ' : 'មិនអាចកែប្រែបានទេ ព្រោះមានអ្នកទទួលរួចហើយ',
              icon: const Icon(Icons.edit_outlined),
              onPressed: !_editable
                  ? null
                  : () async {
                      final saved = await context.push<bool>('/document/out/edit/${widget.id}');
                      if (saved == true) _load();
                    },
            ),
        ],
      ),
      body: _loading && doc == null
          ? const LoadingList(count: 4)
          : _error.isNotEmpty && doc == null
              ? ErrorState(_error, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: () async {
                    ref.read(apiClientProvider).clearCache();
                    await _load();
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      if (_isPending) _pendingBanner(),
                      if (_canAct) _actCard(),
                      if (_isOwner && !_canAct && !_isPending && !_alreadySent) _sendCard(),
                      const SizedBox(height: 4),
                      _senderCard(doc!),
                      const SizedBox(height: 12),
                      _infoCard(doc),
                      const SizedBox(height: 12),
                      SectionCard(
                        title: 'ឯកសារគោល',
                        child: _files(asList(doc['document_main_url'])),
                      ),
                      const SizedBox(height: 12),
                      _refsCard(doc),
                      const SizedBox(height: 12),
                      SectionCard(title: 'ការតាមដានឯកសារ', child: TrackingPanel(data: _tracking)),
                    ],
                  ),
                ),
    );
  }

  // ---------- sections ----------
  Widget _pendingBanner() {
    final note = s(_mine?['note']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: AppColors.warn.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ឯកសារនេះកំពុងរង់ចាំការទទួលពីអ្នក',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              if (note.isNotEmpty) ...[const SizedBox(height: 6), Text('ការណែនាំ: $note')],
              const SizedBox(height: 6),
              const Text('សូមទទួលឯកសារជាមុនសិន ទើបអាចបញ្ជូនបន្ត រុញត្រឡប់ ឬបញ្ចប់បាន។',
                  style: TextStyle(color: AppColors.muted)),
              if (_actionError.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_actionError, style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _receive,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.move_to_inbox_rounded),
                label: const Text('ទទួលឯកសារ'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noteField(String label) => TextField(
        controller: _note,
        enabled: !_busy,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
      );

  Widget _receiverCard({required Widget footer}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ReceiverCard(
          tree: _tree,
          users: _users,
          myOfficeId: _myOfficeId,
          myUserId: _myUserId,
          office: _toOffice,
          userId: _toUserId,
          disabled: _busy,
          onOfficeChanged: (v) => setState(() => _toOffice = v),
          onUserChanged: (v) => setState(() => _toUserId = v),
          footer: footer,
        ),
      );

  Widget _errorLine() => _actionError.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_actionError, style: const TextStyle(color: AppColors.danger)),
        );

  Widget _actCard() {
    return _receiverCard(
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectField(
            label: 'លំហូរឯកសារ',
            options: [for (final f in _flows) Option(s(f['_id']), s(f['name']))],
            value: _flowId,
            enabled: !_busy,
            onChanged: (v) => setState(() => _flowId = v),
          ),
          const SizedBox(height: 14),
          _noteField('កំណត់ចំណាំ / ការណែនាំ'),
          _errorLine(),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy || !_hasReceiver ? null : _forward,
            icon: const Icon(Icons.share_outlined),
            label: Text(_busy ? 'កំពុងដំណើរការ...' : 'បញ្ជូនបន្ត'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _return,
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('រុញត្រឡប់'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _finish,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('បញ្ចប់'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sendCard() {
    return _receiverCard(
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _noteField('ការណែនាំដល់អ្នកទទួល'),
          _errorLine(),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy || !_hasReceiver ? null : _send,
            icon: const Icon(Icons.send_rounded),
            label: Text(_busy ? 'កំពុងផ្ញើ...' : 'ផ្ញើ'),
          ),
        ],
      ),
    );
  }

  Widget _senderCard(Json doc) {
    final from = s(asObj(doc['send_from_office_id'])['name']).isNotEmpty
        ? s(asObj(doc['send_from_office_id'])['name'])
        : s(asObj(doc['office_id_open'])['name']);
    final offices = asList(doc['send_to_office_id']).map((o) => s(o['name'])).where((e) => e.isNotEmpty).join(', ');
    final users = asList(doc['send_to_user_id']).map(personName).where((e) => e.isNotEmpty).join(', ');
    return SectionCard(
      title: 'អ្នកផ្ញើ និងអ្នកទទួល',
      child: Column(
        children: [
          InfoRow('អង្គភាពផ្ញើ', from),
          InfoRow('អ្នកផ្ញើ', personName(doc['send_from_user_id'])),
          InfoRow('កាលបរិច្ឆេទផ្ញើ', formatDateTime(doc['date_sent'])),
          InfoRow('បង្កើតដោយ', personName(doc['created_by'])),
          InfoRow('អង្គភាពទទួល', offices),
          InfoRow('អ្នកប្រើប្រាស់ទទួល', users),
        ],
      ),
    );
  }

  Widget _infoCard(Json doc) {
    return SectionCard(
      title: 'ព័ត៌មានឯកសារ',
      child: Column(
        children: [
          InfoRow('កម្មវត្ថុ', s(doc['objective'])),
          InfoRow('លេខឯកសារ', s(doc['number_document'])),
          InfoRow('កាលបរិច្ឆេទចុះហត្ថលេខា', formatDate(doc['date_sign'])),
          InfoRow('កាលបរិច្ឆេទចូល', formatDate(doc['date_in'])),
          InfoRow('ចុះលេខចេញ', formatDate(doc['date_registration_document'])),
          InfoRow('ប្រភេទឯកសារ', s(asObj(doc['document_type_id'])['name'])),
          InfoRow('ក្របខណ្ឌឯកសារ', s(asObj(doc['framework_id'])['name'])),
          InfoRow('លំហូរឯកសារ', s(asObj(doc['status_of_process_id'])['name'])),
          InfoRow('កំណត់សម្គាល់', s(doc['note_from_user'])),
        ],
      ),
    );
  }

  Widget _refsCard(Json doc) {
    final refs = asList(doc['reference_document']);
    return SectionCard(
      title: 'ឯកសារយោង',
      child: refs.isEmpty
          ? const Text('គ្មានឯកសារយោង', style: TextStyle(color: AppColors.muted))
          : Column(
              children: [
                for (var i = 0; i < refs.length; i++)
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(bottom: i == refs.length - 1 ? 0 : 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.soft.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ឯកសារយោងទី ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        InfoRow('លេខឯកសារ', s(refs[i]['number_document'])),
                        InfoRow('កាលបរិច្ឆេទចុះហត្ថលេខា', formatDate(refs[i]['date_sign'])),
                        InfoRow('កម្មវត្ថុ', s(refs[i]['objective'])),
                        const SizedBox(height: 4),
                        _files(asList(refs[i]['files'])),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _files(List<Json> files) {
    if (files.isEmpty) return const Text('គ្មានឯកសារ', style: TextStyle(color: AppColors.muted));
    return Column(
      children: [
        for (final f in files)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 0,
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
            child: ListTile(
              leading: Icon(
                fileIconName(f) == 'pdf'
                    ? Icons.picture_as_pdf_outlined
                    : fileIconName(f) == 'image'
                        ? Icons.image_outlined
                        : Icons.insert_drive_file_outlined,
                color: AppColors.primary,
              ),
              title: Text(
                s(f['original_name']).isEmpty ? s(f['public_id']) : s(f['original_name']),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text([s(f['format']), formatBytes(f['bytes'])].where((e) => e.isNotEmpty).join(' · ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openFile(f),
            ),
          ),
      ],
    );
  }
}
