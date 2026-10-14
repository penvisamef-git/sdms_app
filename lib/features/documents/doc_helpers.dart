import '../../core/json.dart';
import '../../widgets/common.dart';

class StatusInfo {
  const StatusInfo(this.label, this.tone);

  final String label;
  final Tone tone;
}

/// Status of a document inside the office (same labels as the web).
const docStatus = <String, StatusInfo>{
  'new': StatusInfo('ថ្មី', Tone.info),
  'process': StatusInfo('កំពុងដំណើរការ', Tone.warn),
  'close': StatusInfo('បិទ', Tone.done),
};

/// Status of one hop of a document to one receiver.
const transferStatus = <String, StatusInfo>{
  'pending': StatusInfo('រង់ចាំទទួល', Tone.warn),
  'received': StatusInfo('បានទទួល', Tone.info),
  'forwarded': StatusInfo('បានបញ្ជូនបន្ត', Tone.done),
  'returned': StatusInfo('បានរុញត្រឡប់', Tone.danger),
  'done': StatusInfo('បានបញ្ចប់', Tone.done),
};

const transferAction = <String, String>{
  'send': 'ផ្ញើ',
  'forward': 'បញ្ជូនបន្ត',
  'return': 'រុញត្រឡប់',
};

/// Is [me] the receiver of this transfer row?
bool isTransferReceiver(Json? t, Json? me) {
  if (t == null || me == null) return false;
  if (t['to_user_id'] != null && s(t['to_user_id']).isNotEmpty) {
    return idOf(t['to_user_id']) == s(me['_id']);
  }
  final office = idOf(me['office_id']);
  return office.isNotEmpty && idOf(t['to_office_id']) == office;
}

/// Names of the offices and users a document was sent to.
String receiverText(Json doc) {
  final names = <String>[
    ...asList(doc['send_to_office_id']).map((o) => s(o['name'])),
    ...asList(doc['send_to_user_id']).map(personName),
  ].where((e) => e.isNotEmpty).toList();
  return names.isEmpty ? '-' : names.join(', ');
}

String fileIconName(Json f) {
  final fmt = s(f['format']).toLowerCase();
  if (fmt == 'pdf') return 'pdf';
  if (const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(fmt)) return 'image';
  return 'file';
}
