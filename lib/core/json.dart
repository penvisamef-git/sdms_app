/// Tiny helpers for the loosely-typed JSON the API returns
/// (a field can be an id string or a populated object).
typedef Json = Map<String, dynamic>;

String s(dynamic v) => v == null ? '' : v.toString();

Json asObj(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Json> asList(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Json>[];

/// "_id" of a populated object, or the id string itself.
String idOf(dynamic v) => v is Map ? s(v['_id']) : s(v);

int asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(s(v)) ?? 0;
}

double? asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(s(v));
}

bool asBool(dynamic v) => v == true || v == 'true';

/// "firstname lastname" of a user object.
String personName(dynamic u) {
  if (u is! Map) return '';
  return '${s(u['firstname'])} ${s(u['lastname'])}'.trim();
}
